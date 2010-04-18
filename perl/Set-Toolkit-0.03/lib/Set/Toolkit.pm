package Set::Toolkit;
use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.03';

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub __do_boolean {
  my $self    = shift;
  my $field   = shift;
  my $default = shift;

  if (@_) {
    $self->{$field} = $_[0] ? 1 : 0;
  }

  $self->{$field} = $default if (not exists $self->{$field});
  return $self->{$field};
}

sub is_ordered {
  my $self = shift;
  return $self->__do_boolean('is_ordered', 0, @_);
}

sub is_unique {
  my $self = shift;
  return $self->__do_boolean('is_unique', 1, @_);
}


### is=>ro
sub _data {
  my $self = shift;
  
  if (not exists $self->{_data}
  or ref($self->{_data}) ne 'ARRAY') {
    $self->{_data} = [];
  }

  return $self->{_data};
};

sub size {
  my $self = shift;
  return scalar(@{$self->_data});
};

sub _filter_duplicates {
  my $self = shift;
  
  my %lookup = ();
  @lookup{@{$self->_data}} = @{$self->_data};

  my @unique = ();

  foreach my $el (@_) {
    if (not exists $lookup{$el}) {
      push @unique, $el;
    }
  }

  return @unique;
}

sub elements {
  my $self = shift;
  
  my @elements = @{$self->_data};

  if ($self->is_ordered) {
    return $self->ordered_elements;
  } else {
    return $self->unordered_elements;
  }
}

sub ordered_elements {
  my $self = shift;
  return @{$self->_data};
}

sub unordered_elements {
  my $self = shift;
  
  my %randomizer = ();
  @randomizer{@{$self->_data}} = @{$self->_data};
  return values(%randomizer);
}

sub insert {
  my $self = shift;
  my @elements = @_;

  if ($self->is_unique) {
    @elements = $self->_filter_duplicates(@elements); 
  }


  push @{$self->_data}, @elements;
}

sub _items_match {
  my ($a, $b) = @_;

  ### If only one is a ref, they don't match.
  if (ref($a) and not ref($b)
  or  ref($b) and not ref($a)) {
    return 0;
  }

  ### If neither is a ref, just do an eq comparison.
  if (not ref($a) and not ref($b)) {
    return ($a eq $b);
  }
  
  ### They're both refs.  If they aren't refs to the same thing, return false.
  if (ref($a) ne ref($b)) {
    return 0;
  }

  ### I don't know how else they could be different...
  return 1;
}

sub remove {
  my $self = shift;
  my @elements = @_;

  LIST: foreach my $el (@elements) {
    ELEMENTS: for (my $i = 0; $i < scalar(@{$self->_data}); $i++) {
      ### If these two items match, do the deed.
      if (_items_match($el,$self->_data->[$i])) {
        ### Splice it out of the element list.
        splice(@{$self->_data}, $i--, 1);
        ### Save a little time if we know this is a unique set.  In that
        ### case, we can just skip to examining the next item in the list
        ### of requested removals.
        next LIST if ($self->is_unique);
      }
    }
  }
}

### Returns all matches (a set) or an empty set
sub search {
  my $self = shift;
  
  my $condition;
  if (scalar(@_) == 1 and ref($_[0]) eq 'HASH') {
    ### This is a hashref, so search by it.
    $condition = $_[0];
  } elsif (scalar(@_) == 1) {
    ### We got a scalar value only... we'll want to compare the value of
    ### the stored thing against it.
    $condition = $_[0];
  } else {
    my %args = @_;
    $condition = \%args;
  }   

  my $resultset = __PACKAGE__->new();

  ### Loop through the elements in the current set, pushing matches into the
  ### result set.
  foreach my $obj (@{$self->_data}) {
    if (_obj_matches_properties($obj, $condition)) {
      $resultset->insert($obj);
    }   
  }   

  ### Always returns a Set::Object thing, meaning we can do chaining.
  return $resultset;
}

### Returns the first matched object or undef.
sub find {
  my $self = shift;
  
  my $condition;
  if (scalar(@_) == 1 and ref($_[0]) eq 'HASH') {
    ### This is a hashref, so search by it.
    $condition = $_[0];
  } elsif (scalar(@_) == 1) {
    ### We got a scalar value only... we'll want to compare the value of
    ### the stored thing against it.
    $condition = $_[0];
  } else {
    my %args = @_;
    $condition = \%args;
  }   

  ### Loop through the elements in the current set, returning the first one
  ### that matches completely.
  foreach my $obj (@{$self->_data}) {
    if (_obj_matches_properties($obj, $condition)) {
      return $obj;
    }   
  }   

  ### No matches.  Return undef.  ->find does *not* chain.
  return undef;
}

sub _obj_matches_properties {
  my $obj = shift;
  my $opt = shift;

  ### If the option we're matching against is not a ref, then we're trying to
  ### compare against a scalar value.
  if (not ref($opt)) {
    if (not ref($obj)) {
      return ($obj eq $opt);
    } else {
      return 0;
    }
  } elsif (not ref($obj)) {
    ### If the constraint *is* a ref, but the thing stored isn't, return false.
    return 0;
  }

  ### Ok, so our constraint is a ref.  We need to assume it's a hashref and
  ### search by property.
  foreach my $field (keys(%$opt)) {
    ### First, if our constraint is a hashref, then we need to test against
    ### the object's properties.  This would look like this:
    ###   $set->find(a=>4);
    if (ref($opt->{$field}) eq 'HASH') {
      if (not _obj_matches_properties($obj->{$field}, $opt->{$field})) {
        return 0;
      }   
    } else {
      my $opt_version = $opt->{$field};
      my $obj_version = undef;
      ### Ok, so we're not comparing the value to a hashref -- that means
      ### we just want to compare the values directly.  In that case, we
      ### want to *prefer* to check against the output of a method, and
      ### fall back to a hash key if necessary (and possible).
      my $can_do = 0;
      eval {$can_do = $obj->can($field)};

      ### If we got a die error, then this object isn't really an object,
      ### it's probably just a hashref that can't do methods.  In that case
      ### let's just check if it has the property.
      if ($@) {
        ### Assume $obj is a hash ref.  If it's not, we want to know that
        ### bad data is being inserted into our set; perl will barf for us.
        if (exists $obj->{$field}) {
          ### If there's such a field in this hashref, set it.
          $obj_version = $obj->{$field};
        } else {
          ### If no such field, we know it's not a match, so return false.
          return 0;
        }
      } else {
        $obj_version = $obj->{$field};
      }

      if (not defined $opt_version and not defined $obj_version) {
        ### Do nothing, this counts as a match.
      } elsif (not defined $opt_version or not defined $obj_version) {
        ### Only one is undef ... no match.
        return 0;
      } elsif ($opt_version ne $obj_version) {
        return 0;
      }
    }
  }

  return 1;
}

=head1 NAME

Set::Toolkit - searchable, orderable, flexible sets of (almost) anything.

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

The Set Toolkit intends to provide a broad, robust interface to sets of
data.  Largely inspired by Set::Object, a default set from the Set Toolkit
should behave similarly enough to those created by Set::Object that 
interchanging between the two is fairly easy and intuitive.

In addition to the set functionality already available around the CPAN,
the Set Toolkit provides the ability to perform fairly complex, chained
searches against the set, ordered and unordered considerations, as well
as the ability to enforce or relax a uniqueness constraint (enforced by
default).

  use Set::Toolkit;

  $set = Set::Toolkit->new();
  $set->insert(
    'a',
    4, 
    {a=>'abc', b=>123},
    {a=>'abc', b=>456, c=>'foo'},
    {a=>'abc', b=>456, c=>'bar'},
    '',
    {a=>'ghi', b=>789, c=>'bar'},
    {
      x => {
        y => "hello",
        z => "world",
      },
    },
  );

  die "we didn't add enough items!"
    if ($set->size < 4);

  ### Find single elements.
  $el1 = $set->find(a => 'ghi');
  $el2 = $set->find(x => { y=>'hello' });

  ### Print "Hello, world!"
  print "Hello, ", $el2->{x}->{z}, "!\n";

  ### Search for result sets.
  ### $resultset will contain:
  ###   {a=>'abc', b=>456, c=>'foo'},
  ###   {a=>'abc', b=>456, c=>'bar'},
  $resultset => $set->search(a => 'abc')
                    ->search(b => 456);

  ### $bar will be: {a=>'ghi', b=>789, c=>'bar'},
  $bar = $set->search(a => 'abc')
             ->search(b => 456)
             ->find(c => 'bar');

  ### Get the elements in the order they were inserted.  These are equivalent:
  @ordered = $set->ordered_elements;

  $set->is_ordered(1);
  @ordered = $set->elements;
  
  ### Get the elements in hash-random order.  These two are equivalent:
  @unordered = $set->unordered_elements

  $set->is_ordered(0);
  @unordered = $set->elements;

=head1 DESCRIPTION

This module implements a set objects that can contain members of (almost) 
any type, and provides a number of attached helpers to allow set and element
manipulation at a variety of levels.  By "almost", I mean that it won't let
you store C<undef> as a value, but not for a good reason:  that's just how
L<Set::Object> did it, and I haven't had a chance to think about the pros
and cons yet.  Probably in the future it'll be a settable flag.

The set toolkit is largely inspired by the work done in Set::Object, but with
some notable differences: this package ...

=over

=item ... provides for I<ordered> sets

=item ... is pure perl.

=item ... is slower for the above reasons (and more!)

=item ... provides mechanisms for searching set elements.

=item ... does not flatten scalars to strings.

=item ... probably some other stuff.

=back

In general, take a look at L<Set::Object> first to see if it will suit your
needs.  If not, give Set::Toolkit a spin.

By default, this package's sets are intended to be functionally identical
to those created by Set::Object (or close to it).  That is, without specifying
differently, sets created from the Set::Toolkit will be an I<unordered> 
collection of things I<without duplication>.

=head1 EXPORT

None at this time.

=head1 FUNCTIONS

=head2 Construction

=head3 new

Creates a new set toolkit object.  Right now it doesn't take parameters,
because I have not codified how it should work.

=head2 Set manipulation

=head3 B<insert>

Insert new elements into the set.  

  ### Create a set object.
  $set = Set::Toolkit->new();
  
  ### Insert two scalars, an array ref, and a hash ref.
  $set->insert('a', 'b', [2,4], {some=>'object'});

Duplicate entries will be silently ignored when the set's B<is_unique>
constraint it set.  (This behavior is likely to change in the future.  What
will probably happen later is the element will be added and masked.  That
will probably be a setting =)

=head3 B<remove>

Removes elements from the set.

  ### Create a set object.
  $set = Set::Toolkit->new();
  
  ### Insert two scalars, an array ref, and a hash ref; the set size will
  ### be 4.
  $set->insert('a', 'b', [2,4], {some=>'object'});

  ### Remove the scalar 'b' from the set.  The set size will be 3.
  $set->remove('b');

Note that removing things removes I<all instances> of it (this only really
matters in non-unique sets).

Removing references might catch you off guard:  though you can B<insert>
object literals, you can't remove them.  That's because each time you create
a new literal, you get a new reference.  Consider:

  ### Create a set object.
  $set = Set::Toolkit->new();
  
  ### Insert two literal hashrefs.
  $set->insert({a => 1}, {a => 2});

  ### Remove a literal hashref.  This will have no effect, because the two
  ### objects (inserted and removed) are I<different references>.
  $set->remove({a => 1});

However, the following should work instead

  ### Create a set object.
  $set = Set::Toolkit->new();
 
  ### Create our two hashes.
  ($hash_a, $hash_b) = ({a=>1}, {a=>2});

  ### Insert the two references.
  $set->insert($hash_a, $hash_b);

  ### Remove a hash reference.  This will work; it's the same reference as
  ### what was inserted.
  $set->remove($hash_a);

Obviously the same applies for all references.

=head2 Set inspection

=head3 B<elements>

Returns a list of the elements in the set.  The content of the list is
sensitive to the set context, defined by B<is_ordered>, B<is_unique>, and
possibly other settings later.

=head3 B<ordered_elements>

Returns a list of the elements in insertion order, regardless of whether the
set thinks its ordered or unordered.  This can be thought of as a temporary
coercion of the set to ordered for the duration of the fetch, only.

=head3 B<unordered_elements>

Returns a list of the elements in a random order, regardless of whether the
set thinks its ordered or unordered.  This can be thought of as a temporary
coercion of the set to unordered for the duration of the fetch, only.

The random order of the set relies on perl's treatment of hash keys
and values.  We're using a hash under the hood.

=head3 B<size>

Returns the size of the set.  This is context sensitive:

  $set = Set::Toolkit->new();
  $set->is_unique(0);
  $set->insert(qw(d e a d b e e f));

  ### Prints:  
  ###   The set size is 8!
  ###   The set size is 5!
  print 'The set size is ', $set->size, '!';
  $set->is_unique(1);
  print 'The set size is ', $set->size, '!';

=head2 Set introspection

=head3 B<is_ordered>

Returns a boolean value depending on whether the set is currently considering 
itself as ordered or unordered.  Also a setter to change the set's context.

=head3 B<is_unique>

Returns a boolean value depending on whether the set is currently considering 
itself as unique or duplicable (with respect to its elements).  Also a setter
to change the set's context.

=head3 B<search> and B<find>

Searching allows you to find subsets of your current set that match certain
criteria.  Some effort has been made to make the syntax as simple as possible,
though some complexity is present in order to provide some power.  

Searches take one argument, a constraint, that can be specified in two primary
ways:

=over

=item As a scalar value

=item As a hash reference

=back

=head4 Scalar searches

Specifying a constraint as a scalar value makes a very simple check against
any scalar values contained in your set (and only such values).  Thus, if you
search for "b", you will get a subset of the parent set that contains one
string "b" for each such occurrance in the super set.

Consider the following:
  
  ### Create a new set.
  $set = Set::Toolkit->new();

  ### Insert some values.
  $set->insert(qw(a b c d e));

  ### Do a search, and then a find.

  ### $resultset is now a set object with one entry: 'b'
  $resultset = $set->search('b');
  
  ### $resultset is now an empty set object (because we didn't insert any
  ### strings "x").
  $resultset = $set->('x');

For scalars, it probably won't generally be useful to use search.  You'll
probably want to use find() instead, which simply returns the value sought,
rather than a set of matches:

  ### Using the set above, $match now contains 'b'.
  my $match = $set->find('b');

However, there is a case in which you might want to use scalar searches:
in sets that are not enforcing uniqueness.

  ### Turn off the uniqueness constraint.
  $set->is_unique(0);

  ### Add some more letters.
  $set->insert(qw(a c e g i j));

  ### Now do some searches:

  ### $resultset will contain <'c','c'>
  $resultset->search('a');

This may be useful for counting occurrances, such as:

  print "There are ", $set->search('a')->size, " occurances of 'a'.\n";

=head4 Property searches

On the other hand, searching by property values will probably be useful
more often.  Consider the following set:

  ### Create our set.
  $works = Set::Toolkit->new();

  ### Insert some complex values:
  $works->insert(
    { name  => {first=>'Franz', last=>'Kafka'},
      title  => 'Metamorphosis',
      date  => '1915'},

    { name  => {first=>'Ovid', last=>'unknown'},
      title  => 'Metamorphosis',
      date  => 'AD 8'},

    { name  => {first=>'Homer', last=>undef},
      title  => 'The Iliad',
      date  => 'unknown'},

    { name  => {first=>'Homer', last=>undef},
      title  => 'The Odyssey',
      date  => 'unknown'},

    { name  => {first=>'Ted', last=>'Chiang'},
      title  => 'Understand',
      date  => '1991'},

    { name  => {first=>'John', last=>'Calvin'},
      title  => 'Institutes of the Christian Religion',
      date  => '1541'},
  );

We can perform an arbitrarily complex subsearch of these fields, as follows:

  ### $homeric_works is now a set object containing the same hash references
  ### as the superset, "works", but only those that matched the first name
  ### "Homer" and the last name B<undef>.
  my $homeric_works = $authors->search({
    name => {
      first => 'Homer',
      last => undef,
  });

  ### We can get a specific work, "The Oddysey," for example, by a second
  ### search (or B<find>):

  ### $oddysey_works is now a set of one.
  my $oddysey_works = $homeric_works->search(title=>'The Odyssey');

  ### We can get the instance (instead of a set) with a B<find>:
  my $oddysey_work = $homeric_works->find(title=>'The Odyssey');

  ### Which we could have gotten more easily by issuing a B<find> on the
  ### original set:
  my $oddysey_work = $works->find(title=>'The Odyssey');

Searches can also be chained, if that's desirable for any reason, and
B<find> can be included in the chain, as long as it is the last link.

Note that this is I<not> a speed-optimized scan at this point (but it
shouldn't be brutally slow in most cases).

  ### Get a resultset of one.
  my $resultset = $works->search(name=>{first=>'Homer'})
                        ->search(title=>'The Iliad');
 
And you can search against multiple values:

  ### Search against title and date to get Ovid's I<Metamorphosis> (yeah, I
  ### realize his was plural, but give me a break here =)

  ### Get the set.
  my $resultset = $works->search(
    title => 'Metamorphosis',
    date  => 'AD 8'
  );

  ### Get the item.
  my $result = $works->find(
    title => 'Metamorphosis',
    date  => 'AD 8'
  );

=head1 When should this module be used?

You might want to use this module if the following are generally true:

=over 

=item You aren't desparate for speed.

=item You want to be able to search (and subsearch!) your sets easily.

=item You want I<ordered> sets.

=back

=head1 When shouldn't this module be used?

This module probably isn't right for you if you:

=over 

=item Need it fast, fast, fast!

=item You don't care about searching your sets.

=item You don't care about ordering your sets.

=back

In these are true, I would take a look at Set::Object instead. 

=head1 NOTES

Set::Toolkit sets contain "things" or "members" or "elements".  I've avoided
saying "objects" because you can really store anything in these sets, from 
scalars, to objects, to references.

Set::Toolkit does not currently support "weak" sets as defined by Set::Object.

Because uniqueness is not enforced by keying into a hash, scalars are not
flattened into strings and will not lose their magicks.

=head1 SPECIAL DISCLAIMER

This is the first module I've released.  I'm open to constructive critiques, 
bug reports, patches, doc patches, requests for documentation clarification,
and so forth.  Be gentle =)

=head1 AUTHOR

Sir Robert Burbridge, C<< <sirrobert at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-set-toolkit at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Set::Toolkit>.  I
will be notified, and then you'll automatically be notified of progress on your bug as I
make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Set::Toolkit

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Set::Toolkit>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Set::Toolkit>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Set::Toolkit>

=item * Search CPAN

L<http://search.cpan.org/dist/Set::Toolkit>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Jean-Louis Leroy and Sam Vilain, the developers/maintainers of 
Set::Object, for lots of concepts, etc.  I'm not actually using any borrowed
code under the hood, but I plan to in the future.

=head1 COPYRIGHT & LICENSE

Copyright 2010 Sir Robert Burbridge, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Set::Toolkit
