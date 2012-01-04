package XML::LibXML::QuerySelector;

use 5.010;
use common::sense;
use utf8;

use XML::LibXML::QuerySelector::ToXPath;
use XML::LibXML;

BEGIN {
	$XML::LibXML::QuerySelector::AUTHORITY = 'cpan:TOBYINK';
	$XML::LibXML::QuerySelector::VERSION   = '0.001';
	
	push @XML::LibXML::Document::ISA, __PACKAGE__;
	push @XML::LibXML::DocumentFragment::ISA, __PACKAGE__;
	push @XML::LibXML::Element::ISA, __PACKAGE__;
}

use Scalar::Util qw/blessed/;

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
		{ $self->_xlxqs_contains($_) ? ($_) : () }
		@{[ $xc->findnodes($xpath) ]};
	
	return wantarray ? @results : XML::LibXML::NodeList->new(@results);
}

sub _xlxqs_contains
{
	my ($self, $node) = @_;
	my $self_path = $self->nodePath;
	my $node_path = $node->nodePath;
	my $sub_node_path = substr $node_path, 0, length $self_path;
	$sub_node_path eq $self_path;
}

sub querySelector
{
	my ($self, $selector_string) = @_;
	my $results = $self->querySelectorAll($selector_string);
	return unless $results->size;
	$results->shift;
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

