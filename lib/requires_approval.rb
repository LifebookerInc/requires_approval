require 'active_record'
require 'errors'


module RequiresApproval

  
  def self.included(klass)
    klass.send(:extend, ClassMethods)
  end

  def approve_all_attributes
    self.approve_attributes(self.fields_requiring_approval)
  end

  # # approve a list of attributes
  def approve_attributes(*attributes)
  
    return true unless self.has_pending_changes?

    # validate an normalize our attributes    
    attributes = self.check_attributes_for_approval(attributes)

    # make sure that all attributes are provided if we have never
    # been approved
    fields_not_being_approved = (self.fields_requiring_approval - attributes)

    if fields_not_being_approved.present? && self.never_approved?
      raise PartialApprovalForNewObject.new(
        "You must approve #{self.fields_requiring_approval.join(", ")} " + 
        "for a new #{self.class.name}"
      )
    end

    attributes.flatten.each do |attr|
      write_attribute(attr, self.latest_unapproved_version.send(attr))
    end

    # if we have approved all requested changes, make our latest
    # unapproved version approved - 
    # this is ALWAYS true for a new record even though its pending_changes
    # hash is forced to have values
    if self.is_first_version? || self.no_pending_changes?
      self.latest_unapproved_version.update_attribute(:is_approved, true)
    else
      # makes our latest_unapproved_version approved and 
      # creates another unapproved version with any remaining 
      # attributes
      self.create_approval_version_record
    end

    self.is_frozen = false

    self.save
    self.reload
    true
  end

  def deny_attributes(*attributes)

    unless self.has_approved_version?
      raise DenyingNeverApprovedError.new
    end

    attributes = self.check_attributes_for_approval(attributes)

    attributes.flatten.each do |attr|
      self.latest_unapproved_version.send("#{attr}=", self.send(attr))
      true
    end

    # if we have denied all changes, remove the record
    unless self.has_pending_changes?
      self.latest_unapproved_version.destroy
    else
      self.latest_unapproved_version.save
    end
    
    self.reload
    true
  end

  # have any of our versions ever been approved?
  def has_approved_version?
    self.versions.count(:conditions => {:is_approved => true}) > 0
  end

  # have we already approved all outstanding changes?
  def has_pending_changes?
    self.pending_changes.present?
  end

  # are we the first version?
  def is_first_version?
    !self.has_approved_version?
  end

  # returns true if there are no changes to approve
  def no_pending_changes?
    !self.has_pending_changes?
  end

  # the changes users have requested since the last approval
  def pending_changes
    return {} if self.latest_unapproved_version.blank?
    
    ret = {}
    # check each field requiring approval
    self.fields_requiring_approval.each do |field|
      
      # if it is the same in the unapproved as in the parent table
      # we skip it
      if self.is_first_version? || 
        self.send(field) != self.latest_unapproved_version.send(field)
        
        # otherwise we get the change set
        ret[field] = {
          # our first version is always nil, regardless of the 
          # defaults in that table
          "was" => self.is_first_version? ? nil : self.send(field), 
          "became" => self.latest_unapproved_version.send(field)
        }
      end
    end
    ret
  end

  protected

  # the attributes that require approval
  def attributes_requiring_approval
    self.attributes.select{|k,v| self.fields_requiring_approval.include?(k)}
  end

  # check if our attributes are valid for approval
  def check_attributes_for_approval(attributes)
     # normalize attributes
    attributes = Array.wrap(attributes).flatten.collect(&:to_s)

    # check for invalid attributes
    invalid_fields = (attributes - self.fields_requiring_approval)
    # if we have fields not requiring approval, raise an error
    if invalid_fields.present?
      raise InvalidFieldsError.new(
        "fields_requiring_approval don't include #{invalid_fields.join(",")}"
      )
    end
    attributes
  end

  # creates the record of an individual approval
  def create_approval_version_record
    outstanding_changes = self.pending_attributes
    # update our old latest_unapproved_version to reflect our changes
    self.latest_unapproved_version.update_attributes(
      self.attributes_requiring_approval.merge(:is_approved => true)
    )
    # reload so this unapproved version is out of our cache and will not 
    # get its foreign key unassigned
    self.latest_unapproved_version(true)

    self.latest_unapproved_version = self.versions_class.new(
      self.attributes_requiring_approval.merge(outstanding_changes)
    )
  end

  # gets the latest unapproved version or creates a new one
  def latest_unapproved_version_with_nil_check
    self.latest_unapproved_version ||= begin
      self.versions_class.new(self.attributes_requiring_approval)
    end
  end

  # has this record never been approved?
  def never_approved?
    !self.has_approved_version?
  end

  # ActiveRecord-style attribute hash for the 
  # requested changes
  def pending_attributes
    ret = {}
    self.pending_changes.each_pair do |k, change|
      ret[k] = change["became"]
    end
    ret
  end

  # the class which our versions are
  def versions_class
    self.class.versions_class
  end

  module ClassMethods

    # adds the correct tables and columns for requires_approval
    def prepare_tables_for_requires_approval
      self.reset_column_information

      # adds is_active to the parent table
      self.add_requires_approval_fields
      self.reset_column_information

      # adds our versions table
      self.drop_versions_table
      self.create_versions_table
      
    end

    def requires_approval_for(*attrs)
      self.set_options(attrs.extract_options!)

      # set up our attributes that require approval
      self.class_attribute :fields_requiring_approval
      self.fields_requiring_approval = attrs.collect(&:to_s)

      # set up delegates
      self.set_up_version_delegates

      # create a blank version before create to handle if no
      # attributes were ever set
      self.before_validation_on_create(
        :latest_unapproved_version_with_nil_check
      )
      
      # create the versions class
      self.create_versions_class
      self.has_many :versions, 
        :class_name => self.versions_class.name,
        :foreign_key => self.versions_foreign_key

      self.has_one :latest_unapproved_version,
        :autosave => true,
        :class_name => self.versions_class.name,
        :foreign_key => self.versions_foreign_key,
        :conditions => [
          "#{self.versions_table_name}.is_approved = ?", false
        ]

      self.set_up_scopes


    end

    # the class which our versions are
    def versions_class
      "#{self.name}::#{self.versions_class_name}".constantize
    end

    protected

    def add_requires_approval_fields
      # add is_frozen
      unless self.column_names.include?("is_frozen")
        self.connection.add_column(
          self.table_name, :is_frozen, :boolean, :default => true
        )
      end
      # add is_deleted
      unless self.column_names.include?("is_deleted")
        self.connection.add_column(
          self.table_name, :is_deleted, :boolean, :default => false
        )
      end
      true
    end

    # create a class
    def create_versions_class
      versions_table_name = self.versions_table_name
      
      self.const_set self.versions_class_name, Class.new(ActiveRecord::Base)
      
      self.versions_class.class_eval do
        self.table_name = versions_table_name
      end
    end

    def create_versions_table
      self.connection.create_table(self.versions_table_name) do |t|
        self.columns.each do |column|
          t.send(column.type, column.name, {
            :default => column.default,
            :limit => column.limit,
            :null => column.null,
            :precision => column.precision,
            :scale => column.scale
          })
        end
        t.integer self.versions_foreign_key
        t.boolean :is_approved, :default => false
      end
      self.connection.add_index(
        self.versions_table_name,
        [self.versions_foreign_key, :is_approved]
      )
    end

    # drop the versions table if it exists
    def drop_versions_table
      if self.connection.tables.include?(self.versions_table_name)
        self.connection.drop_table(self.versions_table_name)
      end
    end

    def set_options(opts = {})
      @versions_class_name = opts.delete(:versions_class_name)
      @version_foreign_key = opts.delete(:versions_foreign_key)
      @versions_table_name = opts.delete(:versions_table_name)
    end

    def set_up_scopes
      self.named_scope(:unapproved, {
        :include => [:latest_unapproved_version],
        :conditions => [
          "#{self.versions_table_name}.id IS NOT NULL"
        ]
      })
    end

    def set_up_version_delegates
      self.fields_requiring_approval.each do |f|
        define_method("#{f}=") do |val|
          # type cast our val so "0" changes to 'false'
          type_casted_val = self.column_for_attribute(f).type_cast(val)
          
          # if we have a latest_unapproved version already, let it handle
          # updates - if not, only create one if the type casted value is 
          # not the same as what is in the parent value
          if self.latest_unapproved_version.present? || 
            type_casted_val != self.send(f)
            
            self.send("#{f}_will_change!")
            self.latest_unapproved_version_with_nil_check.send("#{f}=", val)
          end
        end
      end
    end

    # class name for our versions
    def versions_class_name
      @versions_class_name ||= "Version"
    end

    # foreign key for our class on the version table
    def versions_foreign_key
      @version_foreign_key ||= "#{self.base_class.name.underscore}_id"
    end

    # table name for our versions
    def versions_table_name
      @versions_table_name ||= "#{self.base_class.name.underscore}_versions"
    end

  end


end

ActiveRecord::Base.send(:include, RequiresApproval)