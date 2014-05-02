# encoding: utf-8
class Manifestation < ActiveRecord::Base
  scope :periodical_master, where(:periodical_master => true)
  scope :periodical_children, where(:periodical_master => false)
  has_many :creates, :dependent => :destroy, :foreign_key => 'work_id'
  has_many :realizes, :dependent => :destroy, :foreign_key => 'expression_id'
  has_many :produces, :dependent => :destroy, :foreign_key => 'manifestation_id'
  has_many :exemplifies, :foreign_key => 'manifestation_id'
  has_many :items, :through => :exemplifies #, :foreign_key => 'manifestation_id'
  has_many :children, :foreign_key => 'parent_id', :class_name => 'ManifestationRelationship', :dependent => :destroy
  has_many :parents, :foreign_key => 'child_id', :class_name => 'ManifestationRelationship', :dependent => :destroy
  has_many :derived_manifestations, :through => :children, :source => :child
  has_many :original_manifestations, :through => :parents, :source => :parent
  belongs_to :manifestation_relationship_type

  validates_presence_of :original_title
  validates :isbn, :uniqueness => true, :allow_blank => true, :unless => proc{ |manifestation| manifestation.series_statement }, :if => proc{ SystemConfiguration.get("manifestation.isbn_unique") }
  validates :nbn, :uniqueness => true, :allow_blank => true
  validates :identifier, :uniqueness => true, :allow_blank => true
  validates :serial_number, 
    :numericality => :only_integer, 
    :allow_blank => true, 
    :if => proc{ |manifestation| manifestation.not_set_serial_number }
  validates :access_address, :url => true, :allow_blank => true, :length => {:maximum => 255}
  validate :check_isbn, :check_issn, :check_lccn, :unless => :during_import

  #validate :check_pub_date
  before_validation :set_wrong_isbn, :check_issn, :check_lccn, :if => :during_import
  before_validation :convert_isbn
  before_create :set_digest
  after_create :clear_cached_numdocs
  before_save :set_date_of_publication, :set_volume_issue_number, :set_date_of_discontinuance
  before_save :set_serial_number, :unless => proc{ |manifestation| manifestation.not_set_serial_number }
  before_save :delete_attachment?
  normalize_attributes :identifier, :pub_date, :isbn, :issn, :nbn, :lccn, :original_title
  attr_accessible :delete_attachment
  attr_accessor :series_statement_id, :not_set_serial_number
  attr_protected :periodical_master

  def check_pub_date
    logger.info "manifestaion#check pub_date=#{self.pub_date}"
    date = self.pub_date.to_s.gsub(' ', '').dup
    return if date.blank?

    unless date =~ /^\d+(-\d{0,2}){0,2}$/
      errors.add(:pub_date); return
    end

    if date =~ /^[0-9]+$/  # => YYYY / YYYYMM / YYYYMMDD
      case date.length
      when 4
        date = "#{date}-01-01"
      when 6
        year = date.slice(0, 4)
        month = date.slice(4, 2)
        date = "#{year}-#{month}-01"
      when 8
        year = date.slice(0, 4)
        month = date.slice(4, 2)
        day = date.slice(6, 2) 
        date = "#{year}-#{month}-#{day}"
      else
        errors.add(:pub_date); return
      end
    else
      date_a = date.split(/\D/) #=> ex. YYYY / YYYY-MM / YYYY-MM-DD / YY-MM-DD
      year = date_a[0]
      month = date_a[1]
      day = date_a[2]
      date = "#{year}-01-01" unless month and day
      date = "#{year}-#{month}-01" unless day
      date = "#{year}-#{month}-#{day}" if year and month and day
    end

    begin
      date = Time.zone.parse(date)
    rescue
      errors.add(:pub_date)
    end
  end

  def check_isbn
    if isbn.present?
      unless  Lisbn.new(isbn).valid?
        errors.add(:isbn)
      end
    end
  end

  def check_issn
    if issn.present?
      self.issn = Lisbn.new(issn)
      unless StdNum::ISSN.valid?(issn)
        errors.add(:issn)
      end
    end
  end

  def check_lccn
    if lccn.present?
      unless StdNum::LCCN.valid?(lccn, true)
        errors.add(:lccn)
      end
    end
  end

  def set_wrong_isbn
    if isbn.present?
      unless Lisbn.new(isbn).valid?
        self.wrong_isbn
        self.isbn = nil
      end
    end
  end

  def convert_isbn
    num = Lisbn.new(isbn) if isbn
    if num
      if num.length == 10
        self.isbn10 = num
        self.isbn = num.isbn13
      elsif num.length == 13
        self.isbn10 = num.isbn10
      end
    end
  end

  def set_date_of_publication
    return if pub_date.blank?
    date = pub_date.gsub(/(\.|\,|\/)/, '-')
    begin
      date = Time.zone.parse("#{date}")
    rescue ArgumentError
      begin
        date = Time.zone.parse("#{date}-01")
        date = date.end_of_month
      rescue ArgumentError
        begin
          date = Time.zone.parse("#{date}-12-01")
          date = date.end_of_month
        rescue ArgumentError
          nil
        end
      end
    end
    self.date_of_publication = date
  end

  def set_date_of_discontinuance
    return if dis_date.blank?
    date = dis_date.gsub(/(\.|\,|\/)/, '-')
    begin
      date = Time.zone.parse("#{date}")
    rescue ArgumentError
      begin
        date = Time.zone.parse("#{date}-01")
        date = date.end_of_month
      rescue ArgumentError
        begin
          date = Time.zone.parse("#{date}-12-01")
          date = date.end_of_month
        rescue ArgumentError
          nil
        end
      end
    end
    self.date_of_discontinuance = date
  end

  def self.cached_numdocs
    Rails.cache.fetch("manifestation_search_total"){ 
      Manifestation.search do
        with(:periodical_master, false)
      end.total
    }
  end

  def clear_cached_numdocs
    Rails.cache.delete("manifestation_search_total")
  end

  def parent_of_series
    original_manifestations
  end

  def number_of_pages
    if self.start_page and self.end_page
      if self.start_page.present? and self.end_page.present?
        if self.start_page.to_s.match(/\D/).nil? and self.end_page.to_s.match(/\D/).nil?
          page = self.end_page.to_i - self.start_page.to_i + 1
        end
      end
    end
  end

  def titles
    title = []
    title << original_title.to_s.strip
    title << title_transcription.to_s.strip
    title << title_alternative.to_s.strip
    #title << original_title.wakati
    #title << title_transcription.wakati rescue nil
    #title << title_alternative.wakati rescue nil
    title
  end

  def set_serial_number
    if self.serial_number_string && self.serial_number_string.tr('０-９','0-9').match(/\d/)
      self.serial_number = self.serial_number_string.tr('０-９','0-9').to_i
    else
#      self.serial_number = nil
    end
  end

  def set_volume_issue_number
    if self.volume_number_string && self.volume_number_string.tr('０-９','0-9').match(/\d/)
      self.volume_number = self.volume_number_string.tr('０-９','0-9').to_i 
    else
      self.volume_number = nil
    end

    if self.issue_number_string && self.issue_number_string.tr('０-９','0-9').match(/\d/)
      self.issue_number = self.issue_number_string.tr('０-９','0-9').to_i
    elsif self.issue_number_string 
      self.issue_number = Date::ABBR_MONTHNAMES.index(self.issue_number_string) 
    end
  end

  def set_next_number(current_volume, current_issue)
    if self.series_statement && self.series_statement.try(:sequence_pattern)
      next_numbers = self.series_statement.sequence_pattern.try(:get_next_number, current_volume, current_issue)
      logger.error next_numbers
      self.volume_number_string = next_numbers[0].try(:to_s)
      self.issue_number_string = next_numbers[1].try(:to_s)
    elsif current_issue
      issue_num = current_issue ? current_issue + 1 : nil
      self.issue_number_string = issue_num.to_s
    end
    serial_num = self.serial_number_string.try(:match, /\d/) ? self.serial_number_string.to_i + 1 : nil rescue nil
    self.serial_number_string = serial_num.to_s if serial_num
  end

  def title
    titles
  end

  def hyphenated_isbn
    Lisbn.new(isbn).parts.join("-")
  end

  def set_digest(options = {:type => 'sha1'})
    if attachment.queued_for_write[:original]
      if File.exists?(attachment.queued_for_write[:original])
        self.file_hash = Digest::SHA1.hexdigest(File.open(attachment.queued_for_write[:original].path, 'rb').read)
      end
    end
  end


  def self.find_by_isbn(isbn)
    lisbn = Lisbn.new(isbn)
    if lisbn.valid?
      #ISBN_Tools.cleanup!(isbn)
      if isbn.size == 10
        Manifestation.where(:isbn => lisbn.isbn13).first || Manifestation.where(:isbn => lisbn).first
      else
        Manifestation.where(:isbn => lisbn).first || Manifestation.where(:isbn => lisbn.isbn10).first
      end
    end
  end

  def acquired_at
    items.order(:acquired_at).first.try(:acquired_at)
  end

  def delete_attachment
    @delete_attachment ||= "0"
  end
  
  def delete_attachment=(value)
    @delete_attachment = value
  end

private
  def delete_attachment?
    self.attachment.clear if @delete_attachment == "1"
  end

end

# == Schema Information
#
# Table name: manifestations
#
#  id                              :integer         not null, primary key
#  original_title                  :text            not null
#  title_alternative               :text
#  title_transcription             :text
#  classification_number           :string(255)
#  identifier                      :string(255)
#  date_of_publication             :datetime
#  date_copyrighted                :datetime
#  created_at                      :datetime
#  updated_at                      :datetime
#  deleted_at                      :datetime
#  access_address                  :string(255)
#  language_id                     :integer         default(1), not null
#  carrier_type_id                 :integer         default(1), not null
#  extent_id                       :integer         default(1), not null
#  start_page                      :integer
#  end_page                        :integer
#  height                          :decimal(, )
#  width                           :decimal(, )
#  depth                           :decimal(, )
#  isbn                            :string(255)
#  isbn10                          :string(255)
#  wrong_isbn                      :string(255)
#  nbn                             :string(255)
#  lccn                            :string(255)
#  oclc_number                     :string(255)
#  issn                            :string(255)
#  price                           :integer
#  fulltext                        :text
#  volume_number_string              :string(255)
#  issue_number_string               :string(255)
#  serial_number_string              :string(255)
#  edition                         :integer
#  note                            :text
#  produces_count                  :integer         default(0), not null
#  exemplifies_count               :integer         default(0), not null
#  embodies_count                  :integer         default(0), not null
#  work_has_subjects_count         :integer         default(0), not null
#  repository_content              :boolean         default(FALSE), not null
#  lock_version                    :integer         default(0), not null
#  required_role_id                :integer         default(1), not null
#  state                           :string(255)
#  required_score                  :integer         default(0), not null
#  frequency_id                    :integer         default(1), not null
#  subscription_master             :boolean         default(FALSE), not null
#  ipaper_id                       :integer
#  ipaper_access_key               :string(255)
#  attachment_file_name            :string(255)
#  attachment_content_type         :string(255)
#  attachment_file_size            :integer
#  attachment_updated_at           :datetime
#  nii_type_id                     :integer
#  title_alternative_transcription :text
#  description                     :text
#  abstract                        :text
#  available_at                    :datetime
#  valid_until                     :datetime
#  date_submitted                  :datetime
#  date_accepted                   :datetime
#  date_caputured                  :datetime
#  file_hash                       :string(255)
#  pub_date                        :string(255)
#  periodical_master               :boolean         default(FALSE), not null
#

