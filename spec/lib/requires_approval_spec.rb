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
      t.timestamps
    end

    class User < ActiveRecord::Base
      requires_approval_for(:first_name, :last_name)
    end

    User.prepare_tables_for_requires_approval

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

      user.approve_attributes(:first_name)

      user.first_name.should eql("Dan")
      # last name was not approved, should still be nil
      user.last_name.should be nil
      user.is_frozen.should be false

      user.requested_changes.should eql({
        "last_name" => {"was" => nil, "became" => "Langevin"}
      })

      # should create an approved version
      user.versions.where(:is_approved => true).count.should eql(1)

    end

  end

  context "#deny_attributes" do
    
    it "should remove the denied attributes from the 
      requested_changes hash" do

      user = User.create(
        :first_name => "Dan", 
        :last_name => "Langevin"
      )
      user.deny_attributes(:first_name)
      user.first_name.should eql(nil)
      user.requested_changes.should eql({
        "last_name" => {"was" => nil, "became" => "Langevin"}
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

  end


end
