# -*- encoding: utf-8 -*-
class Item < ActiveRecord::Base
  scope :recent, where(['items.created_at >= ?', Time.zone.now.months_ago(1)])
  has_one :exemplify, :dependent => :destroy
  has_one :manifestation, :through => :exemplify

  validates :item_identifier, :allow_blank => true, :uniqueness => true, :format => {:with => /\A[0-9A-Za-z_]+\Z/}
  validates :url, :url => true, :allow_blank => true, :length => {:maximum => 255}
  validate :check_acquired_at_string
  validates_date :acquired_at, :allow_blank => true

  normalize_attributes :item_identifier

  before_save :set_acquired_at
  attr_accessor :library_id, :manifestation_id, :use_restriction_id

  def title
    manifestation.try(:original_title)
  end

  def check_acquired_at_string
    return if self.acquired_at_string.blank?
    if self.acquired_at_string =~ /^\d{4}-(0?[1-9]|1[0-2])-(0?[1-9]|[12]\d|3[01])$|^\d{4}-(0?[1-9]|1[0-2])$|^\d{4}$/
      dates = self.acquired_at_string.split('-')
      return if dates.size < 3
      date = Time.zone.parse(self.acquired_at_string) rescue nil 
      if date
        mm = dates[1].match(/^[1-9]$/) ? "0#{dates[1]}" : dates[1]
        return if date.strftime("%m") == mm
      end
    end
    errors.add(:acquired_at_string)
  end

  def select_acquired_at
    if self.acquired_at
      return self.acquired_at.strftime("%Y%m")
    else
      return Time.now.strftime("%Y%m")
    end
  end

  def set_acquired_at
    return if acquired_at_string.blank?
    begin
      date = Time.zone.parse("#{acquired_at_string}")
    rescue ArgumentError
      begin
        date = Time.zone.parse("#{acquired_at_string}-01")
        date = date.end_of_month
      rescue ArgumentError
        begin
          date = Time.zone.parse("#{acquired_at_string}-12-01")
          date = date.end_of_month
        rescue ArgumentError
          nil
        end
      end
    end
    self.acquired_at = date
  end

  private
  def self.to_format(num)
    num.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
  end

  def self.get_object_method(obj,array)
    _obj = obj.send(array.shift)
    return get_object_method(_obj, array) if array.present?
    return _obj
  end

end

# == Schema Information
#
# Table name: items
#
#  id                          :integer         not null, primary key
#  call_number                 :string(255)
#  item_identifier             :string(255)
#  circulation_status_id       :integer         not null
#  checkout_type_id            :integer         default(1), not null
#  created_at                  :datetime
#  updated_at                  :datetime
#  deleted_at                  :datetime
#  shelf_id                    :integer         default(1), not null
#  include_supplements         :boolean         default(FALSE), not null
#  checkouts_count             :integer         default(0), not null
#  owns_count                  :integer         default(0), not null
#  resource_has_subjects_count :integer         default(0), not null
#  note                        :text
#  curl                         :string(255)
#  price                       :integer
#  lock_version                :integer         default(0), not null
#  required_role_id            :integer         default(1), not null
#  state                       :string(255)
#  required_score              :integer         default(0), not null
#  acquired_at                 :datetime
#  bookstore_id                :integer
#

