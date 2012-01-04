use 5.010;
use common::sense;
use utf8;

{
	package XML::LibXML::QuerySelector;

	use XML::LibXML qw//;

	BEGIN
	{
		$XML::LibXML::QuerySelector::AUTHORITY = 'cpan:TOBYINK';
		$XML::LibXML::QuerySelector::VERSION   = '0.001';
		
		push @XML::LibXML::Document::ISA, __PACKAGE__;
		push @XML::LibXML::DocumentFragment::ISA, __PACKAGE__;
		push @XML::LibXML::Element::ISA, __PACKAGE__;
	}

	my $contains = sub 
	{
		my ($self, $node) = @_;
		my $self_path = $self->nodePath;
		my $node_path = $node->nodePath;
		my $sub_node_path = substr $node_path, 0, length $self_path;
		$sub_node_path eq $self_path;
	};

	sub querySelectorAll
	{
		my ($self, $selector_string) = @_;
		my $selector = XML::LibXML::QuerySelector::ToXPath->new($selector_string);
		my $xpath = $selector->to_xpath(prefix => 'defaultns');
		
		my $document = $self->nodeName =~ /^#/ ? $self : $self->ownerDocument;
		my $xc = XML::LibXML::XPathContext->new($document);
		$xc->registerNs(defaultns => $document->documentElement->namespaceURI);
		
		if ($document == $self)
		{
			return $xc->findnodes($xpath);
		}
		
		my @results = map
			{ $self->$contains($_) ? ($_) : () }
			@{[ $xc->findnodes($xpath) ]};
		
		wantarray ? @results : XML::LibXML::NodeList->new(@results);
	}

	sub querySelector
	{
		my ($self, $selector_string) = @_;
		my $results = $self->querySelectorAll($selector_string);
		return unless $results->size;
		$results->shift;
	}
}

{
	package XML::LibXML::QuerySelector::ToXPath;
	
	use Carp qw//;
	
	our @ISA;
	BEGIN
	{
		$XML::LibXML::QuerySelector::ToXPath::AUTHORITY = 'cpan:TOBYINK';
		$XML::LibXML::QuerySelector::ToXPath::VERSION   = '0.001';
		
		require HTML::Selector::XPath;
		@ISA = qw/HTML::Selector::XPath/;
	}
	
	# XXX: Identifiers should also allow any characters U+00A0 and higher, and any
	# escaped characters.
	my $ident = qr/(?![0-9]|-[-0-9])[-_a-zA-Z0-9]+/;
	
	my $reg = {
		# tag name/id/class
		element => qr/^([#.]?)([a-z0-9\\*_-]*)((\|)([a-z0-9\\*_-]*))?/i,
		# attribute presence
		attr1   => qr/^\[ \s* ($ident) \s* \]/x,
		# attribute value match
		attr2   => qr/^\[ \s* ($ident) \s*
			( [~|*^\$!]? = ) \s*
			(?: ($ident) | "([^"]*)" ) \s* \] /x,
		badattr => qr/^\[/,
		attrN   => qr/^:not\((.*?)\)/i, # this should be a parentheses matcher instead of a RE!
		pseudo  => qr/^:([()a-z0-9_+-]+)/i,
		# adjacency/direct descendance
		combinator => qr/^(\s*[>+~\s](?!,))/i,
		# rule separator
		comma => qr/^\s*,\s*/i,
	};
	
	foreach (qw/
			selector_to_xpath
			convert_attribute_match
			_generate_child
			nth_child
			nth_last_child
			parse_pseudo
		/)
	{
		no strict 'refs';
		*{$_} = \&{"$ISA[0]\::$_"};
	}
	
	sub to_xpath
	{
		my $self = shift;
		my $rule = $self->{expression} or return;
		my %parms = @_;
		my $root = $parms{root} || '/';
		
		my @parts = ("$root/");
		my $last_rule = '';
		my @next_parts;
		
		my $tag;
		my $wrote_tag;
		my $tag_index;
		my $root_index = 0; # points to the current root
		# Loop through each "unit" of the rule
		while (length $rule && $rule ne $last_rule)
		{
			$last_rule = $rule;
			
			$rule =~ s/^\s*|\s*$//g;
			last unless length $rule;
			
			# Prepend explicit first selector if we have an implicit selector
			# (that is, if we start with a combinator)
			if ($rule =~ /$reg->{combinator}/)
			{
				$rule = "* $rule";
			}
			
			# Match elements
			if ($rule =~ s/$reg->{element}//)
			{
				my ($id_class,$name,$lang) = ($1,$2,$3);
				
				# to add *[1]/self:: for follow-sibling
				if (@next_parts)
				{
					push @parts, @next_parts; #, (pop @parts);
					@next_parts = ();
				}
				
				if ($id_class eq '')
				{
					$tag = $name || '*';
				}
				else
				{
					$tag = '*';
				}
				
				if (defined $parms{prefix} and not $tag =~ /[*:|]/)
				{
					$tag = join ':', $parms{prefix}, $tag;
				}
				
				if (! $wrote_tag++)
				{
					push @parts, $tag;
					$tag_index = $#parts;
				}
				
				# XXX Shouldn't the RE allow both, ID and class?
				if ($id_class eq '#')
				{ # ID
					push @parts, "[\@id='$name']";
				}
				elsif ($id_class eq '.')
				{ # class
					push @parts, "[contains(concat(' ', \@class, ' '), ' $name ')]";
				}
			}
			
			# Match attribute selectors
			if ($rule =~ s/$reg->{attr2}//)
			{
				push @parts, "[", convert_attribute_match( $1, $2, $^N ), "]";
			}
			elsif ($rule =~ s/$reg->{attr1}//)
			{
				# If we have no tag output yet, write the tag:
				if (! $wrote_tag++)
				{
					push @parts, '*';
					$tag_index = $#parts;
				}
				push @parts, "[\@$1]";
			}
			elsif ($rule =~ $reg->{badattr})
			{
				Carp::croak "Invalid attribute-value selector '$rule'";
			}
			
			# Match negation
			if ($rule =~ s/$reg->{attrN}//)
			{
				my $sub_rule = $1;
				if ($sub_rule =~ s/$reg->{attr2}//)
				{
					push @parts, "[not(", convert_attribute_match( $1, $2, $^N ), ")]";
				}
				elsif ($sub_rule =~ s/$reg->{attr1}//)
				{
					push @parts, "[not(\@$1)]";
				}
				elsif ($rule =~ $reg->{badattr})
				{
					Carp::croak "Invalid attribute-value selector '$rule'";
				}
				else
				{
					my $xpath = selector_to_xpath($sub_rule);
					$xpath =~ s!^//!!;
					push @parts, "[not(self::$xpath)]";
				}
			}
			
			# Ignore pseudoclasses/pseudoelements
			while ($rule =~ s/$reg->{pseudo}//)
			{
				if ( my @expr = $self->parse_pseudo($1, \$rule) )
				{
					push @parts, @expr;
				}
				elsif ( $1 eq 'first-child')
				{
					# Translates to :nth-child(1)
					push @parts, nth_child(1);
				}
				elsif ( $1 eq 'last-child')
				{
					push @parts, nth_last_child(1);
				}
				elsif ( $1 eq 'only-child')
				{
					push @parts, nth_child(1), nth_last_child(1);
				}
				elsif ($1 =~ /^lang\(([\w\-]+)\)$/)
				{
					push @parts, "[\@xml:lang='$1' or starts-with(\@xml:lang, '$1-')]";
				}
				elsif ($1 =~ /^nth-child\((\d+)\)$/)
				{
					push @parts, nth_child($1);
				}
				elsif ($1 =~ /^nth-child\((\d+)n(?:\+(\d+))?\)$/)
				{
					push @parts, nth_child($1, $2||0);
				}
				elsif ($1 =~ /^nth-last-child\((\d+)\)$/)
				{
					push @parts, nth_last_child($1);
				}
				elsif ($1 =~ /^nth-last-child\((\d+)n(?:\+(\d+))?\)$/)
				{
					push @parts, nth_last_child($1, $2||0);
				}
				elsif ($1 =~ /^first-of-type$/)
				{
					push @parts, "[1]";
				}
				elsif ($1 =~ /^nth-of-type\((\d+)\)$/)
				{
					push @parts, "[$1]";
				}
				elsif ($1 =~ /^contains\($/)
				{
					$rule =~ s/^\s*"([^"]*)"\s*\)\s*$//
						or die "Malformed string in :contains(): '$rule'";
					push @parts, qq{[text()[contains(string(.),"$1")]]};
				}
				elsif ( $1 eq 'root')
				{
					# This will give surprising results if you do E > F:root
					$parts[$root_index] = $root;
				}
				elsif ( $1 eq 'empty')
				{
					push @parts, "[not(* or text())]";
				}
				else
				{
					Carp::croak "Can't translate '$1' pseudo-class";
				}
			}
			
			# Match combinators (whitespace, >, + and ~)
			if ($rule =~ s/$reg->{combinator}//)
			{
				my $match = $1;
				if ($match =~ />/)
				{
					push @parts, "/";
				}
				elsif ($match =~ /\+/)
				{
					push @parts, "/following-sibling::*[1]/self::";
					$tag_index = $#parts;
				}
				elsif ($match =~ /\~/)
				{
					push @parts, "/following-sibling::";
				}
				elsif ($match =~ /^\s*$/)
				{
					push @parts, "//"
				}
				else
				{
					die "Weird combinator '$match'"
				}
				
				# new context
				undef $tag;
				undef $wrote_tag;
			}
			
			# Match commas
			if ($rule =~ s/$reg->{comma}//)
			{
				push @parts, " | ", "$root/"; # ending one rule and beginning another
				$root_index = $#parts;
				undef $tag;
				undef $wrote_tag;
			}
		}
		return join '', @parts;
	}
}

__FILE__
__END__

=head1 NAME

XML::LibXML::QuerySelector - add querySelector and querySelectorAll methods to XML::LibXML::Node

=head1 SYNOPSIS

  my $document = XML::LibXML->new->parse_file('my.xhtml');
  my $warning  = $document->querySelector('p.warning');
  print $warning->toString if defined $warning;

=head1 DESCRIPTION

This module defines a class (it has no constructor so perhaps closer to an
abstract class or a role)XML::LibXML::QuerySelector, and sets itself up as
a superclass (not a subclass) of L<XML::LibXML::Document>,
L<XML::LibXML::DocumentFragment> and L<XML::LibXML::Element>, thus making
its methods available to objects of those classes.

Yes, this is effectively monkey-patching, but it's performed in a
I<relatively> safe manner.

=head2 Methods

The methods provided by this module are defined in the W3C Candidate
Recomendation "Selectors API Level 1" L<http://www.w3.org/TR/selectors-api/>.

=over

=item C<< querySelector($selector) >>

Given a CSS selector, returns the first match or undef if there are no
matches.

=item C<< querySelectorAll($selector) >>

Given a CSS selector, returns all matches as a list, or if called in scalar
context, as an L<XML::LibXML::NodeList>.

=back

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=XML-LibXML-QuerySelector>.

=head1 SEE ALSO

L<HTML::Selector::XPath>,
L<XML::LibXML>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

