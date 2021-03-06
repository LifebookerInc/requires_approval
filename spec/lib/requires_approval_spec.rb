require 'spec_helper'

describe RequiresApproval do
  
  before(:all) do

    ActiveRecord::Base.establish_connection({
      "adapter" => "sqlite3",
      "database" => File.join(File.dirname(__FILE__), "..", "support", "db.sqlite")
    })

    ActiveRecord::Base.connection.create_table(:users, :force => true) do |t|
      t.string(:first_name)
      t.string(:last_name)
      t.date(:birthday)
      t.boolean(:is_alive, :default => true)
      t.timestamps
    end

    class User < ActiveRecord::Base
      attr_accessible(
        :birthday,
        :first_name,
        :is_alive,
        :last_name
      )
      requires_approval_for(:first_name, :last_name, :is_alive)
    end

    User.prepare_tables_for_requires_approval

  end

  context "#pending_changes" do

    it "gives back all attributes when it is a new record" do
      user = User.create(
        :first_name => "Dan", 
        :last_name => "Test",
        :is_alive => true
      )
      user.pending_changes.should eql({
        "first_name" => {
          "was" => nil,
          "became" => "Dan"
        },
        "last_name" => {
          "was" => nil,
          "became" => "Test"
        },
        "is_alive" => {
          "was" => nil,
          "became" => true
        }
      })
    end

  end


  context "setup" do

    context "database" do

      it "should create a versions table" do
        User.connection.tables.should include "user_versions"
      end

      it "should add an is_active column to the parent table" do
        User.column_names.should include "is_frozen"
        col = User.columns.select{|c| c.name == "is_frozen"}.first
        col.type.should be :boolean
        col.default.should be true
      end

      it "should add an is_deleted column to the parent table" do
        User.column_names.should include "is_deleted"
        col = User.columns.select{|c| c.name == "is_deleted"}.first
        col.type.should be :boolean
        col.default.should be false
      end

    end

    context "version class" do

      it "should create an ActiveRecord class for its versions" do
        defined?(User::Version).should eql "constant"
        User::Version.table_name.should eql("user_versions")
      end

      it "should provide a getter for its versions class" do
        User.versions_class.should be User::Version
      end

    end

    context "options" do
      
      before(:all) do
        conn = ActiveRecord::Base.connection
        
        conn.create_table(:posts, :force => true) do |t|
          t.string(:title)
          t.string(:body)
          t.date(:published_at)
          t.timestamps
        end

        class Post < ActiveRecord::Base
          requires_approval_for(:title, :body, {
            :versions_table_name => "blah_blah",
            :versions_foreign_key => "test_id",
            :versions_class_name => "SuperVersion"
          })
        end
        Post.prepare_tables_for_requires_approval

      end

      it "should create a custom-named subclass" do
        defined?(Post::SuperVersion).should_not be_nil
      end

      it "should allow for custom table names" do
        Post::SuperVersion.table_name.should eql("blah_blah")
      end

      it "should allow for a custom foreign key" do
        assn = Post.reflect_on_association(:versions)
        assn.options[:foreign_key].should eql("test_id")

        assn = Post.reflect_on_association(:latest_unapproved_version)
        assn.options[:foreign_key].should eql("test_id")

      end

    end

  end

  context "scopes" do

    before(:each) do
      User.delete_all
    end

    it "should add an unapproved scope that finds records 
      that have pending changes" do

      user = User.create!(
        :first_name => "Dan", 
        :last_name => "Langevin",
        :birthday => Date.today
      )
      # has unapproved changes
      User.unapproved.should include user

      # approve them and it should not match the scope
      user.approve_all_attributes
      User.unapproved.should_not include user

    end

  end

  context "saving" do

    it "should create a new version as blank with is_frozen true, is_deleted 
      false, and the requires approval attributes saved in the versions 
      table" do
      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin",
        :birthday => Date.today
      )
      user.is_frozen.should be true
      user.is_deleted.should be false
      user.versions.length.should eql 1

      # requires_approval attributes should not be set on the parent record
      user.first_name.should be nil
      user.last_name.should be nil

      # regular attributes should be set
      user.birthday.should_not be nil

      # requires_approval attributes should be set on the version record
      user.versions.last.first_name.should eql "Dan"
      user.versions.last.last_name.should eql "Langevin"

    end

    it "should update the latest_unapproved_version 
      when a field that requires approval has changed" do
      
      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin"
      )
      version = user.latest_unapproved_version
      version.first_name.should eql("Dan")
      version.last_name.should eql("Langevin")

      user.update_attribute(:first_name, "Blah")

      version = user.latest_unapproved_version(true)
      version.reload.first_name.should eql("Blah")
    end

    it "should initialize a new latest_unapproved_version with
      the attributes of the previously approved version" do

      user = User.create(
        :first_name => "Dan",
        :last_name => "Langevin"
      )
      user.approve_all_attributes

      user.first_name = "Other"
      user.save

      user.reload

      user.latest_unapproved_version.last_name.should eql("Langevin")
      user.approve_all_attributes

      user.first_name.should eql("Other")
      user.last_name.should eql("Langevin")

    end

    it "should not create new versions when attributes are not actually
      updated" do

      user = User.create(
        :first_name => "Dan",
        :last_name => "Langevin"
      )
      user.approve_all_attributes
      user.reload

      user.latest_unapproved_version.should be nil

      user.update_attributes(
        :first_name => user.first_name,
        :last_name => user.last_name
      )
      user.reload
      user.latest_unapproved_version.should be nil


    end

    it "should allow you to modify attributes after an unapproved version
      has been created" do

      user = User.create(
        :first_name => "Dan",
        :last_name => "Langevin"
      )

      user.approve_all_attributes

      user.update_attributes(:first_name => "X")
      user.update_attributes(:first_name => "Dan")

      user.approve_all_attributes
      user.reload.first_name.should eql("Dan")

    end


  end

  context ".validates_approved_field" do

    it "should delegate to the requires_approval field" do
      User.class_eval do 
        validates_approved_field :first_name,
          :presence => true
      end

      user = User.new
      user.should_not be_valid
      errors = user.errors[:"latest_unapproved_version.first_name"]
      errors.should include "can't be blank"

    end

  end

  context "#approve_all_attributes" do

    it "should flag the latest_unapproved_version as approved, set is_frozen
      to false and update all attributes" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin"
      )
      user.approve_all_attributes

      user.first_name.should eql("Dan")
      user.last_name.should eql("Langevin")
      user.is_frozen.should be false

      user.latest_unapproved_version.should be nil
    end

  end

  context "#approve_attributes" do

    it "should flag the selected values as approved and create a 
      new latest_unapproved_version to hold changes that were not
      approved" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin"
      )
      user.approve_all_attributes

      user.update_attributes(
        :first_name => "New First",
        :last_name => "New Last"
      )

      user.approve_attributes(:first_name)

      user.first_name.should eql("New First")
      # last name was not approved, should still be nil
      user.last_name.should eql "Langevin"
      user.is_frozen.should be false

      user.pending_changes.should eql({
        "last_name" => {"was" => "Langevin", "became" => "New Last"}
      })

      # should create an approved version
      user.versions.where(:is_approved => true).count.should be > 0

    end

    it "should throw an error if you try to approve fields that do not require approval
      or do not exist" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin",
        :birthday => Date.today
      )
      user.approve_attributes(:first_name, :last_name, :is_alive)
      user.update_attributes({
        :first_name => "New Name", 
        :last_name => "New Last Name"
      })
      
      # doesn't exist
      lambda{user.approve_attributes(:x)}.should raise_error(RequiresApproval::InvalidFieldsError)
      # doesn't require approval
      lambda{user.approve_attributes(:birthday)}.should raise_error(RequiresApproval::InvalidFieldsError)

    end

    it "should throw an error if you try to approve only some of the fields that require approval
      in a newly created object" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin",
        :birthday => Date.today
      )
      lambda{user.approve_attributes(:first_name)}.should raise_error(
        RequiresApproval::PartialApprovalForNewObject
      )

    end

    it "should return true if you approve an already approved
      record" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin",
        :birthday => Date.today
      )
      user.approve_all_attributes

      user.approve_all_attributes.should be true

    end

    it "should not approve the latest unapproved version if it is invalid" do

      user = User.new(
        :first_name => "Dan", 
        :last_name => "Langevin",
        :birthday => Date.today
      )

      user.stubs(:save => false)
      user.approve_all_attributes.should eql false

    end

  end

  context "#deny_attributes" do
    
    it "should remove the denied attributes from the 
      pending_changes hash" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin"
      )
      user.approve_all_attributes

      user.update_attributes(
        :first_name => "Test",
        :last_name => "User"
      )

      user.deny_attributes(:first_name)
      user.first_name.should eql("Dan")
      user.pending_changes.should eql({
        "last_name" => {"was" => "Langevin", "became" => "User"}
      })


    end

    it "should remove the unapproved version all together when all 
      attributes are denied" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin"
      )
      user.approve_all_attributes

      user.update_attributes(
        :first_name => "ABC",
        :last_name => "DEFG"
      )
      user.deny_attributes(:first_name, :last_name)
      user.latest_unapproved_version.should be nil

    end

    it "should throw an error if you try to deny 
      fields that do not require approval or do not exist" do

      u = User.create( 
        :first_name => "Dan",
        :last_name => "Langevin",
        :birthday => Date.today
      )
      u.approve_all_attributes

      u.update_attributes(:first_name => "A", :last_name => "B")
      
      # doesn't exist
      lambda{u.deny_attributes(:x)}.should raise_error(RequiresApproval::InvalidFieldsError)
      # doesn't require approval
      lambda{u.deny_attributes(:birthday)}.should raise_error(RequiresApproval::InvalidFieldsError)

    end

    it "should throw an error if you try to deny fields on a never-approved object" do

      u = User.create( 
        :first_name => "Dan",
        :last_name => "Langevin",
        :birthday => Date.today
      )

      lambda{u.deny_attributes(:first_name, :last_name)}.should raise_error(
        RequiresApproval::DenyingNeverApprovedError
      )
    end

    it "should set is_frozen to false when denying all attributes" do

      u = User.create( 
        :first_name => "Dan",
        :last_name => "Langevin",
        :birthday => Date.today
      )

      u.approve_all_attributes

      u.update_attributes(:first_name => "Changed!", :is_frozen => true)
      u.is_frozen?.should eql(true)

      u.deny_attributes(:first_name)
      u.is_frozen?.should eql(false)

    end

  end

   context "#has_approved_version?" do

    it "should return true if a version has ever been approved" do
      user = User.create(:first_name => "Dan", :last_name => "Langevin")
      user.approve_all_attributes
      user.has_approved_version?.should be true
    end

    it "should return false if no version has ever been approved" do
      user = User.create(:first_name => "Dan", :last_name => "Langevin")
      user.has_approved_version?.should be false
    end

  end

  context "#has_pending_changes?" do

    let(:user) do
      User.new
    end

    it "should return true if the provider has no outstanding changes" do
      user.stubs(:pending_changes => {})
      user.has_pending_changes?.should be false
    end

    it "should return false if the provider has outstanding changes" do
      user.stubs(:pending_changes => {
        "last_name" => {"was" => "L", "became" => "T"}
      })
      user.has_pending_changes?.should be true
    end

  end



end
