class Exemplify < ActiveRecord::Base
  belongs_to :manifestation
  belongs_to :item

  validates_associated :manifestation, :item
  validates_presence_of :manifestation_id, :item_id
  # validates_uniqueness_of :item_id

  # TODO
  logger.error "############### Frbr_exemplify! ###############"
  validates_uniqueness_of :manifestation_id,
    :if => proc { logger.error SystemConfiguration.get("manifestation.has_one_item");logger.error "############################";SystemConfiguration.get("manifestation.has_one_item") }
  validates_uniqueness_of :item_id,
    :if => proc { logger.error SystemConfiguration.get("manifestation.has_one_item");logger.error "############################";SystemConfiguration.get("manifestation.has_one_item") }
  # TODO

  after_save :reindex
  after_destroy :reindex
  after_create :create_lending_policy, :unless => proc{SystemConfiguration.isWebOPAC}

  acts_as_list :scope => :manifestation_id

  def self.per_page
    10
  end

  def reindex
    manifestation.try(:index)
    item.try(:index)
  end

  def create_lending_policy
    UserGroupHasCheckoutType.available_for_item(item).each do |rule|
      LendingPolicy.create!(:item_id => item.id, :user_group_id => rule.user_group_id, :fixed_due_date => rule.fixed_due_date, :loan_period => rule.checkout_period, :renewal => rule.checkout_renewal_limit)
    end
  end
end

# == Schema Information
#
# Table name: exemplifies
#
#  id               :integer         not null, primary key
#  manifestation_id :integer         not null
#  item_id          :integer         not null
#  type             :string(255)
#  position         :integer
#  created_at       :datetime
#  updated_at       :datetime
#

