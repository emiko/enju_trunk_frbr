class Create < ActiveRecord::Base
  belongs_to :work, :class_name => 'Manifestation', :foreign_key => 'work_id'

  validates_associated :work
  validates_presence_of :agent_id, :work_id
  validates_uniqueness_of :work_id, :scope => :agent_id

  acts_as_list :scope => :work
  attr_accessible :work_id, :agent_id, :work, :agent
end

# == Schema Information
#
# Table name: creates
#
#  id         :integer         not null, primary key
#  agent_id  :integer         not null
#  work_id    :integer         not null
#  position   :integer
#  type       :string(255)
#  created_at :datetime
#  updated_at :datetime
#

