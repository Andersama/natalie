require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#include? with String" do
  it "returns true if self contains other_str" do
    "hello".include?("lo").should == true
    "hello".include?("ol").should == false
  end

  it "ignores subclass differences" do
    "hello".include?(StringSpecs::MyString.new("lo")).should == true
    StringSpecs::MyString.new("hello").include?("lo").should == true
    StringSpecs::MyString.new("hello").include?(StringSpecs::MyString.new("lo")).should == true
  end

  it "tries to convert other to string using to_str" do
    other = mock('lo')
    other.should_receive(:to_str).and_return("lo")

    "hello".include?(other).should == true
  end

  it "raises a TypeError if other can't be converted to string" do
    -> { "hello".include?([])       }.should raise_error(TypeError)
    -> { "hello".include?('h'.ord)  }.should raise_error(TypeError)
    -> { "hello".include?(mock('x')) }.should raise_error(TypeError)
  end

  # NATFIXME: Implement EUC-JP encoding
  xit "raises an Encoding::CompatibilityError if the encodings are incompatible" do
    pat = "ア".encode Encoding::EUC_JP
    -> do
      "あれ".include?(pat)
    end.should raise_error(Encoding::CompatibilityError)
  end
end
