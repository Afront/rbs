require "test_helper"

class RBS::CommentTest < Minitest::Test
  include TestHelper

  def test_concat
    skip 'test is broken'
    buffer = RBS::Buffer.new(name: Pathname("foo.rbs"), content: <<-CONTENT)
123
abc
    CONTENT

    old_location = RBS::Location.new(buffer: buffer, start_pos: 0, end_pos: 3)
    new_location = RBS::Location.new(buffer: buffer, start_pos: 4, end_pos: 7)

    old_comment = RBS::AST::Comment.new(string: 'foo', location: old_location)

    expected_comment = RBS::AST::Comment.new(string: 'foobar', location: old_location.concat(new_location))
    old_comment = old_comment.concat(string: 'bar', location: new_location)

    assert_equal expected_comment, old_comment
    assert_equal 'foobar', old_comment.string
    assert_equal expected_comment.location, old_comment.location
  end

  # def test_concat2
  #   old_string = "World to world.\n"
  #   old_location = RBS::Location.new(buffer: '', start_pos: 0, end_pos: 17) #, source: old_string)
  #   old_comment = RBS::AST::Comment.new(string: old_string, location: old_location)

  #   new_string = "This is a ruby code?\n"
  #   new_location = RBS::Location.new(buffer: '', start_pos: 18, end_pos: 40) #, source: new_string)
  #   new_comment = RBS::AST::Comment.new(string: new_string, location: new_location)

  #   expected_comment = RBS::AST::Comment.new(string: 'foobar', location: old_location.concat(new_location))
  #   old_comment.concat(string: new_string, location: new_location)
  #   assert_equal expected_comment, old_comment
  #   assert_equal 'foobar', old_comment.string
  #   assert_equal expected_comment.location, old_comment.location
  # end

  def test_code_comment
    RBS::Parser.parse_signature(<<-EOF).yield_self do |foo_decl,|
# Passes each element of the collection to the given block. The method
# returns `true` if the block never returns `false` or `nil` . If the
# block is not given, Ruby adds an implicit block of `{ |obj| obj }` which
# will cause [all?](Enumerable.downloaded.ruby_doc#method-i-all-3F) to
# return `true` when none of the collection members are `false` or `nil` .
#
# If instead a pattern is supplied, the method returns whether `pattern
# === element` for every collection member.
#
#     %w[ant bear cat].all? { |word| word.length >= 3 } #=> true
#     %w[ant bear cat].all? { |word| word.length >= 4 } #=> false
#     %w[ant bear cat].all?(/t/)                        #=> false
#     [1, 2i, 3.14].all?(Numeric)                       #=> true
#     [nil, true, 99].all?                              #=> false
#     [].all?                                           #=> true
class Foo
end
    EOF

      assert_instance_of RBS::AST::Declarations::Class, foo_decl
      assert_equal <<-EOF, foo_decl.comment.string
Passes each element of the collection to the given block. The method
returns `true` if the block never returns `false` or `nil` . If the
block is not given, Ruby adds an implicit block of `{ |obj| obj }` which
will cause [all?](Enumerable.downloaded.ruby_doc#method-i-all-3F) to
return `true` when none of the collection members are `false` or `nil` .

If instead a pattern is supplied, the method returns whether `pattern
=== element` for every collection member.

    %w[ant bear cat].all? { |word| word.length >= 3 } #=> true
    %w[ant bear cat].all? { |word| word.length >= 4 } #=> false
    %w[ant bear cat].all?(/t/)                        #=> false
    [1, 2i, 3.14].all?(Numeric)                       #=> true
    [nil, true, 99].all?                              #=> false
    [].all?                                           #=> true
EOF
    end
  end
end

# RuntimeError: ["self: ",
#  "World to world.\n",
#  #<RBS::Location:2620 @buffer=, @pos=0...17, source='# World to world.', start_line=1, start_column=0>,
#  "other: ",
#  "This is a ruby code?\n",
#  #<RBS::Location:2640 @buffer=, @pos=18...40, source='# This is a ruby code?', start_line=2, start_column=0>]
