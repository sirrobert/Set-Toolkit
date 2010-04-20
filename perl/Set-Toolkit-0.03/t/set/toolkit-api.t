use strict;
use warnings;

use Test::More qw(no_plan);
ok(1, 'baseline');

use Set::Toolkit;

sub set {Set::Toolkit->new(@_)};

my $default_set = sub {
  my $set = set();
  ### Insert some scalars and some hashrefs.
  $set->insert(qw(a b c));
  $set->insert(
    {a => 123, b => 'abc'},
    {a => 123, b => 'def'},
    {a => 456, b => 'hij'},
  );
  return $set;
};

{ ### Testing construction
  my $desc = "testing construction";
  my $set = Set::Toolkit->new();
  isa_ok($set, 'Set::Toolkit', "$desc: set isa Set::Toolkit");
}

{ ### Testing insertion.
  my $desc = "scalar insertion";
  my $set = set();
  
  ### Make sure inserted elements update the set size.
  $set->insert('a');
  is($set->size, 1, "$desc: size is updated");

  ### Make sure sets are unique by default (and they know it).
  $set->insert('a');
  is($set->size, 1, "$desc: sets are unique by default");
  is($set->is_unique, 1, "$desc: sets *know* they are unique by default");

  ### Multiple unique inserts.
  $set->insert(qw(b c));
  is($set->size, 3, "$desc: multiple unique inserts work");

  ### Multiple duplicate inserts (nothing should get inserted).
  $set->insert(qw(b c));
  is($set->size, 3, "$desc: multiple dupes don't get inserted");

  ### Multiple mixed inserts add only unique entries..
  $set->insert(qw(d c e a));
  is($set->size, 5, "$desc: mixed (dup/unique) only insert unique");
}

{ ### Testing disorder (by default)
  my $desc = "unordered by default";
  my $set = $default_set->();
  
  ### An ordered set will have the order: a b c {...}, {...}, {...}
  ### but this set should be unordered by default.
  my @els = $set->elements;
  is(scalar(@els), 6, "$desc: the ->elements method returns all values");  
  isnt($els[0], 'a', "$desc: the elements are shuffled");

  ### Fetching ordered from an unordered set (coercing order for a moment).
  @els = $set->ordered_elements;
  is($els[0], 'a', "$desc: order can be coerced");

  ### Setting the set to be ordered mid-stream.
  $set->is_ordered(1);
  @els = $set->elements;
  is($els[0], 'a', "$desc: order can be required");

  ### Disorder can be coerced
  @els = $set->unordered_elements;
  isnt($els[0], 'a', "$desc: disorder can be coerced");

}

{ ### Testing adding hashes 
  my $desc = "ref insertion";
  my $set = set();

  ### Set up a baseline -- a set with some scalars in it.
  $set->insert(qw(a b c));
  $set->insert({abc => 123});
  is($set->size, 4, "$desc: inserted a hashref after some scalars");
}


{ ### Testing find
  my $desc = 'find';
  my $set = $default_set->();

  ### We can find scalars in the list by value
  my $b = $set->find('b');
  is($b, 'b', "$desc: we can find scalars in the set");
  
  ### We can't find scalars not in the list.
  my $x = $set->find('x');
  is($x, undef, "$desc: we get undef when searching for scalars not in the set");

  my $hashref = $set->find(a=>'456');
  ok(ref($hashref) eq 'HASH', "$desc: find returned a hashref");
  is($hashref->{a}, 456,   "$desc: found the correct search param");
  is($hashref->{b}, 'hij', "$desc: secondary properties present");
}

{ ### Testing search
  my $desc = "search";
  my $set = $default_set->();

  ### Searching should return a Set::Toolkit object.
  my $resultset = $set->search('a');
  isa_ok($resultset, 'Set::Toolkit', "$desc: searching for a scalar returns a resultset");
  is($resultset->size, 1, "$desc: the resultset has the right number of items");

  ### Search by hash key=>value pairs.
  $resultset = $set->search(a=>123);
  isa_ok($resultset, 'Set::Toolkit', "$desc: searching for a hashref pair returns a resultset");
  is($resultset->size, 2, "$desc: the resultset has the right number of items");

  ### Chaining searches
  $resultset = $set->search(a=>123)->search(b=>'def');
  is($resultset->size, 1, "$desc: chained searches return sets with the right number of items");
}

{ ### Testing removal
  my $desc = "removal";
  my $set = $default_set->();

  ### Initialize the set and make sure it's good for testing.
  $set->remove('b');
  is($set->size, 5, "$desc: removing a scalar decrements size");

}









