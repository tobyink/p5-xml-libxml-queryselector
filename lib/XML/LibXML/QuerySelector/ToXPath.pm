package XML::LibXML::QuerySelector::ToXPath;

use strict;
use 5.008_001;
our $VERSION = '0.001';

require Exporter;
our @EXPORT_OK = qw(selector_to_xpath);
*import = \&Exporter::import;

use Carp;

sub selector_to_xpath {
    __PACKAGE__->new(shift)->to_xpath(@_);
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


sub new {
    my($class, $exp) = @_;
    bless { expression => $exp }, $class;
}

sub selector {
    my $self = shift;
    $self->{expression} = shift if @_;
    $self->{expression};
}

sub convert_attribute_match {
    my ($left,$op,$right) = @_;
    # negation (e.g. [input!="text"]) isn't implemented in CSS, but include it anyway:
    if ($op eq '!=') {
        "\@$left!='$right'";
    } elsif ($op eq '~=') { # substring attribute match
        "contains(concat(' ', \@$left, ' '), ' $right ')";
    } elsif ($op eq '*=') { # real substring attribute match
        "contains(\@$left, '$right')";
    } elsif ($op eq '|=') {
        "\@$left='$right' or starts-with(\@$left, '$right-')";
    } elsif ($op eq '^=') {
        "starts-with(\@$left,'$^N')";
    } elsif ($op eq '$=') {
        "ends-with(\@$left,'$^N')";
    } else { # exact match
        "\@$left='$^N'";
    }
};

sub _generate_child {
    my ($direction,$a,$b) = @_;
    if ($a == 0) { # 0n+b
        $b--;
        "[count($direction-sibling::*) = $b and parent::*]"
    } elsif ($a > 0) { # an + b
        return "[not((count($direction-sibling::*)+1)<$b) and ((count($direction-sibling::*) + 1) - $b) mod $a = 0 and parent::*]"
    } else { # -an + $b
        $a = -$a;
        return "[not((count($direction-sibling::*)+1)>$b) and (($b - (count($direction-sibling::*) + 1)) mod $a) = 0 and parent::*]"
    };
};

sub nth_child {
    my ($a,$b) = @_;
    if (@_ == 1) {
        ($a,$b) = (0,$a);
    };
    _generate_child('preceding', $a, $b);
};

sub nth_last_child {
    my ($a,$b) = @_;
    if (@_ == 1) {
        ($a,$b) = (0,$a);
    };
    _generate_child('following', $a, $b);
};

sub to_xpath {
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
    while (length $rule && $rule ne $last_rule) {
        $last_rule = $rule;

        $rule =~ s/^\s*|\s*$//g;
        last unless length $rule;

        # Prepend explicit first selector if we have an implicit selector
        # (that is, if we start with a combinator)
        if ($rule =~ /$reg->{combinator}/) {
            $rule = "* $rule";
        };

        # Match elements
        if ($rule =~ s/$reg->{element}//) {
            my ($id_class,$name,$lang) = ($1,$2,$3);

            # to add *[1]/self:: for follow-sibling
            if (@next_parts) {
                push @parts, @next_parts; #, (pop @parts);
                @next_parts = ();
            }

            if ($id_class eq '') {
                $tag = $name || '*';
            } else {
                $tag = '*';
            }

            if (defined $parms{prefix} and not $tag =~ /[*:|]/) {
                $tag = join ':', $parms{prefix}, $tag;
            }

            if (! $wrote_tag++) {
                push @parts, $tag;
                $tag_index = $#parts;
            };

            # XXX Shouldn't the RE allow both, ID and class?
            if ($id_class eq '#') { # ID
                push @parts, "[\@id='$name']";
            } elsif ($id_class eq '.') { # class
                push @parts, "[contains(concat(' ', \@class, ' '), ' $name ')]";
            };
        };

        # Match attribute selectors
        if ($rule =~ s/$reg->{attr2}//) {
            push @parts, "[", convert_attribute_match( $1, $2, $^N ), "]";
        } elsif ($rule =~ s/$reg->{attr1}//) {
            # If we have no tag output yet, write the tag:
            if (! $wrote_tag++) {
                push @parts, '*';
                $tag_index = $#parts;
            };
            push @parts, "[\@$1]";
        } elsif ($rule =~ $reg->{badattr}) {
            Carp::croak "Invalid attribute-value selector '$rule'";
        }

        # Match negation
        if ($rule =~ s/$reg->{attrN}//) {
            my $sub_rule = $1;
            if ($sub_rule =~ s/$reg->{attr2}//) {
                push @parts, "[not(", convert_attribute_match( $1, $2, $^N ), ")]";
            } elsif ($sub_rule =~ s/$reg->{attr1}//) {
                push @parts, "[not(\@$1)]";
            } elsif ($rule =~ $reg->{badattr}) {
                Carp::croak "Invalid attribute-value selector '$rule'";
            } else {
                my $xpath = selector_to_xpath($sub_rule);
                $xpath =~ s!^//!!;
                push @parts, "[not(self::$xpath)]";
            #} else {
            #    Carp::croak "Can't translate '$sub_rule' inside :not()";
            }
        }

        # Ignore pseudoclasses/pseudoelements
        while ($rule =~ s/$reg->{pseudo}//) {
            if ( my @expr = $self->parse_pseudo($1, \$rule) ) {
                push @parts, @expr;
            } elsif ( $1 eq 'first-child') {
                # Translates to :nth-child(1)
                push @parts, nth_child(1);
            } elsif ( $1 eq 'last-child') {
                push @parts, nth_last_child(1);
            } elsif ( $1 eq 'only-child') {
                push @parts, nth_child(1), nth_last_child(1);
            } elsif ($1 =~ /^lang\(([\w\-]+)\)$/) {
                push @parts, "[\@xml:lang='$1' or starts-with(\@xml:lang, '$1-')]";
            } elsif ($1 =~ /^nth-child\((\d+)\)$/) {
                push @parts, nth_child($1);
            } elsif ($1 =~ /^nth-child\((\d+)n(?:\+(\d+))?\)$/) {
                push @parts, nth_child($1, $2||0);
            } elsif ($1 =~ /^nth-last-child\((\d+)\)$/) {
                push @parts, nth_last_child($1);
            } elsif ($1 =~ /^nth-last-child\((\d+)n(?:\+(\d+))?\)$/) {
                push @parts, nth_last_child($1, $2||0);
            } elsif ($1 =~ /^first-of-type$/) {
                push @parts, "[1]";
            } elsif ($1 =~ /^nth-of-type\((\d+)\)$/) {
                push @parts, "[$1]";
            } elsif ($1 =~ /^contains\($/) {
                $rule =~ s/^\s*"([^"]*)"\s*\)\s*$//
                    or die "Malformed string in :contains(): '$rule'";
                push @parts, qq{[text()[contains(string(.),"$1")]]};
            } elsif ( $1 eq 'root') {
                # This will give surprising results if you do E > F:root
                $parts[$root_index] = $root;
            } elsif ( $1 eq 'empty') {
                push @parts, "[not(* or text())]";
            } else {
                Carp::croak "Can't translate '$1' pseudo-class";
            }
        }

        # Match combinators (whitespace, >, + and ~)
        if ($rule =~ s/$reg->{combinator}//) {
            my $match = $1;
            if ($match =~ />/) {
                push @parts, "/";
            } elsif ($match =~ /\+/) {
                push @parts, "/following-sibling::*[1]/self::";
                $tag_index = $#parts;
            } elsif ($match =~ /\~/) {
                push @parts, "/following-sibling::";
            } elsif ($match =~ /^\s*$/) {
                push @parts, "//"
            } else {
                die "Weird combinator '$match'"
            }

            # new context
            undef $tag;
            undef $wrote_tag;
        }

        # Match commas
        if ($rule =~ s/$reg->{comma}//) {
            push @parts, " | ", "$root/"; # ending one rule and beginning another
            $root_index = $#parts;
            undef $tag;
            undef $wrote_tag;
        }
    }
    return join '', @parts;
}

sub parse_pseudo { 
    # nop
}    

1;

__END__

=head1 NAME

XML::LibXML::QuerySelector::ToXPath - CSS Selector to XPath compiler

=head1 DESCRIPTION

Modified version of L<HTML::Selector::XPath>.

Hopefully at least some of these changes will get rolled into the upstream.

=head1 COPYRIGHT

Tatsuhiko Miyagawa 2006-2011

Max Maischein 2011-

Toby Inkster 2012-

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
