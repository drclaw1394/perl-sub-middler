package Sub::Middler;
use 5.024000;
use strict;
use warnings;
use feature "refaliasing";


our $VERSION = 'v0.4.0';
use Export::These qw<linker>;

sub new {
	#simply an array...	
	bless [], __PACKAGE__;
}

# register sub refs to middleware makers
sub register {
  no warnings "experimental";
	\my @middleware=$_[0];	#self
	my $sub=$_[1];
  #die "Middleware must be a CODE reference" unless ref($sub) eq "CODE";
	push @middleware, $sub;
	return $_[0]; #allow chaining
}

*append=\&register;
*add=\&register;


# Link together sub and give each one an index 
# Required argument is the 'dispatcher' which is the end point to call
# 
sub _sink_sub;
sub link {
  no warnings "experimental";

  #die "A CODE reference is required when linking middleware" unless(@_ >=2 and ref $_[1] eq "CODE");
  

	\my @self=shift;	#self;

	my $dispatcher=_sink_sub shift, 1;


  my @args=@_;

	my @mw;  # The generated subs

  my @middleware=@self;
  for(@middleware){
    $_=_sink_sub $_;
  }

	for my $i (reverse 0..@middleware-1){
		my $maker=$middleware[$i];
		my $next=($i==@middleware-1)?$dispatcher:$mw[$i+1];	
		

		$mw[$i]=$maker->($next, $i, @args);
	}

	@middleware?$mw[0]:$dispatcher;
}

sub  linker {
  my $dispatch=pop; 

  my $chain=Sub::Middler->new;
  $chain->register($_) for @_; 
  $chain->link($dispatch);
  
}

sub _sink_sub {
  my $in=$_[0];
  my $is_dispatch=$_[1];

  return $in if ref $in eq "CODE";

  my $wrap=sub {
    my $next=shift;
    my $out;

    for (ref $in){


      if(/SCALAR/){
        $out=$is_dispatch
        ?sub {
          $$in.="@{$_[0]}";
          $_[1] and $_[1]->(); # Auto call call back
        }
        :sub {
          #Convert into string
          $$in.="@{$_[0]}";
          &$next;
        }
      }

      elsif(/ARRAY/){

        $out=$is_dispatch
        ?sub {
          # Copy and append into array,
          push @$in, @{$_[0]};
          $_[1] and $_[1]->();
        }
        :sub {
          # Copy and append into array,
          push @$in, @{$_[0]};
          &$next;
        }
      }

      elsif(/HASH/) {
        $out=$is_dispatch
        ?sub {
          #  copy into hash
          for (my $i=0; $i<$_[0]->@*; $i+=2){
            $in->{$_[0][$i]}=$_[0][$i+1];
          }
          ############################
          # for my($k,$v)(@{$_[0]}){ #
          #   $in->{$k}=$v;          #
          # }                        #
          ############################
          $_[1] and $_[1]->();
        }
        :sub {
          #  copy into hash
          for (my $i=0; $i<$_[0]->@*; $i+=2){
            $in->{$_[0][$i]}=$_[0][$i+1];
          }
          ############################
          # for my($k,$v)(@{$_[0]}){ #
          #   $in->{$k}=$v;          #
          # }                        #
          ############################
          &$next;
        }
      }


      elsif(/REF/){
        my $r=$$in; 
        if(ref $r eq "CODE"){
          # treat a ref to a code ref as 
          $out=$is_dispatch
          ?sub {
            my @res=&$r;
            $_[1] and $_[1]->();
          }

          :sub {
            my @res=&$r;
            #$next->(@res);
            &$next;
          }
        }
        else {
          die "should not get here";
        }
      }
      else {
        die "Could not link unkown reference: ". ref $in; 
      }
    }
    $out;
  };
  $is_dispatch?$wrap->():$wrap;
}

1;

=head1 NAME

Sub::Middler - Middleware subroutine chaining

=head1 SYNOPSIS

  use strict;
  use warings;
  use Sub::Middler;

  
  my @array;
  my %hash;
  my $scalar;

  # append results in variables
  my $head=linker 
    # Short cut to store (copy/append) in array
    \@array       
    # Short cut to modifiy inputs
    =>\sub { $_*=2 for @{$_[0]}},
    # Short cut to store in hash
    =>\%hash,
    # Short cut to stringyfiy and append to scalar
    =>\$scalar;
  

  $head->([1,2,3,4,], sub {...})
  #         inputs      ready cb


  use strict;
  use warnings;
  use Sub::Middler;

  my $middler=Sub::Middler->new;

  $middler->register(mw1(x=>1));
  $middler->register(mw2(y=>10));

  my $head=$middler->link(
    sub {
      print "Result: $_[0]\n";
    }
  );

  $head->(0); # Call the Chain

  # Middleware 1
  sub mw1 {
    my %options=@_;
    sub {
      my ($next, $index, @optional)=@_;
      sub {
        my $work=$_[0]+$options{x};
        $next->($work);
      }
    }
  }

  # Middleware 2
  sub mw2 {
    my %options=@_;
    sub {
      my ($next, $index, @optional)=@_;
      sub {
        my $work= $_[0]*$options{y};
        $next->( $work);
      }
    }
  }

=head1 DESCRIPTION

A small module, facilitating linking subroutines together, acting as middleware
,filters or chains with low runtime overhead.

To achieve this, the  'complexity' is offloaded to the definition of
middleware/filters subroutines. They must be wrapped in subroutines
appropriately to facilitate the lexical binding of linking variables.

This differs from other 'sub chaining' modules as it does not use a loop
internally to iterate over a list of subroutines at runtime. As such there is
no implicit synchronous call to the 'next' item in the chain. Each stage can run
the following stage synchronously or asynchronously or not at all. Each element
in the chain is responsible for how and when it calls the 'next'.

Finally the arguments and signatures of each stage of middleware are completely
user defined and are not interfered with by this module. This allows reuse of
the C<@_> array in calling subsequent stages for ultimate performance if you
know what you're doing.

As a general guide it's suggested the last argument to a stage be a subroutine
reference to allow callbacks and asynchronous usage. Instead of a flat list of
multiple inputs into a stage, it is suggested to also contain these in an array

From v0.4.0, shortcuts can be used to to bypass writing the nestled
subroutines subroutines for some common use cases. A reference to a
SCALAR/ARRAY/HASH/CODE can be used instead of custom middleware

=head1 API

=head2 Inline linking

  linker mw1, ..., dispatch

From v0.3.0, the C<linker> subroutine is exported and will do an inline build
and link for a given middleware and dispatch routine

The return value is the head of the linked chain, and is equivalent to created
a C<Sub::Middler> object, adding middleware, and the calling the link method.


=head2 Short Cuts

  
Instead of writing custom middleware, references to variables and CODE can be
used instead.

If an array reference is used, all elements from the first argument will be
appended to the array

If an hash reference is used, the elements from the first argument will be
treated as key value pairs and set the corresponding elements in the target
hash

If a scalar reference is use, the elements from the first argument will be
converted to strings and appending to the target variable


If a reference is a CODE reference is used, the underlying subroutine is
expected to modify the first argument elements in place. The return value is
not used.


In all the above cases, the next link in the chain is automatically called with
the same arguments, making chaining and saving intermediate values easy


=head2 Managing a chain

=head3 new
  
    my $object=Sub::Middler->new;

Creates a empty middler object ready to accept middleware. The object is a
blessed array reference which stores the middleware directly.

=head3 register

    $object->register(my_middlware());

Appends the middleware to the internal list for later linking.

=head3 append, add

Alias for register

=head3 link

    $object->link($last,[@args]);

Links together the registered middleware in the sequence of addition. Each
middleware is intrinsically linked to the next middleware in the list. The last
middleware being linked to the C<$last> argument, which must be a code ref. 

The C<$last> ref MUST be  a regular subroutine reference, acting as the
'kernel' as described in following sections.

Calls C<die> if C<$last> is not a code ref.

Any optional additional arguments C<@args> are passed to this function are
passed on to each 'maker' sub after the C<$next> and C<$index>, parameters.
This gives an alternative approach to distributing configuration data to each
item in the chain prior to runtime. It is up to each item's maker sub to store
relevant passed values as they see fit.

=head2 Creating Middleware

To achieve low over head in linking middleware, functional programming
techniques (higher order functions) are utilised. This also give the greatest
flexibility to the middleware, as signatures are completely user defined.

The trade off is that the middleware must be defined in a certain code
structure. While this isn't difficult, it takes a minute to wrap your head
around.


=head3 Middlware Definition

Middleware must be a subroutine (top/name) which returns a anonymous subroutine
(maker), which also returns a anonymous subroutine to perform work (kernel).

This sounds complicated by this is what is looks like in code:

  sub my_middleware {                 (1) Top/name subroutine
    my %options=@_;                       Store any config
   
    sub {                             (2) maker sub is returned
      my ($next, $index, @optional)=@_;   (3) Must store at least $next

      sub {                           (4) Returns the kernel sub
        # Code here implements your middleware
        # %options are lexically accessable here
        # as are the @optional parameters
        

        # Execute the next item in the chain
        $next->(...);                 (5) Does work and calls the next entry


                                      (6) Post work if applicable 
      }
    }
  }

=over

=item Top Subroutine

The top sub routine (1) can take any arguments you desire and can be called
what you like. The idea is it represents your middleware/filter and stores any
setup lexically for the B<maker> sub to close over. It returns the B<maker>
sub.

=item Maker Subroutine

This anonymous sub (2) closes over the variables stored in B<Top> and is the
input to this module (via C<register>). When being linked (called) by this
module it is provided at least two arguments: the reference to the next item in
the chain and the current middleware index. These B<MUST> be stored to be
useful, but can be called anything you like (3).
      
Any optional/additional arguments supplied during a call to C<link> are also
used as arguments 'as is' to all maker subroutines in the chain.


=item Kernel subroutine

This anonymous subroutine (4) actually performs the work of the
middleware/filter. After work is done, the next item in the chain must be
called explicitly (5).  This supports synchronous or asynchronous middleware.
Any extra work can be performed after the chain is completed after this call
(6).

=back


=head2 LINKING CHAINS

Multiple chains of middleware can be linked together. This needs to be done in
reverse order. The last chain after being linked, becomes the C<$last> item
when linking the preceding chain and so on.


=head2 EXAMPLES

The synopsis example can be found in the examples directory of this
distribution.


=head1 SEE ALSO

L<Sub::Chain>  and L<Sub::Pipeline> links together subs. They provide other
features that this module does not. 

These iterate over a list of subroutines at runtime to achieve named subs etc.
where as this module pre links subroutines together, reducing overhead.


=head1 AUTHOR

Ruben Westerberg, E<lt>drclaw@mac.comE<gt>

=head1 REPOSITORTY and BUGS

Please report any bugs via git hub: L<https://github.com/drclaw1394/perl-sub-middler>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2025 by Ruben Westerberg

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl or the MIT
license.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE.
=cut

