#!/usr/bin/perl -w

use strict;

use Getopt::Std;
use Pod::Usage;
use XML::DOM;
use WAP::wbxml;

my %opts;
getopts('hp:v', \%opts);

if ($opts{v}) {
	print "WAP::wbxml $WbXml::VERSION\n";
	print "$0\n";
	print "Perl $] on $^O\n";
	exit;
}
pod2usage(-verbose => 1) if ($opts{h});
pod2usage() unless (scalar @ARGV == 1);

my $infile = $ARGV[0];
my $parser = new XML::DOM::Parser;
my $doc = $parser->parsefile($infile);

my $xml_decl = $doc->getXMLDecl();						# not in DOM Spec
my $encoding = $xml_decl ? $xml_decl->getEncoding() : undef;
my $publicid = $doc->getDoctype()->getPubId();			# not in DOM Spec
die "no PublicId.\n" unless ($publicid);

my $rules = WbRules::Load($opts{p});
my $wbxml = new WbXml($rules,$publicid);
my $output = $wbxml->compile($doc,$encoding);
my $filename = $wbxml->outfile($infile);

open OUT,"> $filename"
		or die "can't open $filename ($!)\n";
binmode OUT,":raw";
print OUT $output;
close OUT;

__END__

=head1 NAME

wbxmlc - WBXML Compiler

=head1 SYNOPSIS

wbxmlc [B<-p> I<path>] I<file>

=head1 OPTIONS

=over 8

=item -h

Display help.

=item -p

Specify the path of rules (the default is WAP/wap.wbrules.xml).

=item -v

Display version.

=back

=head1 DESCRIPTION

B<wbxmlc> parses the given input XML file and generates a binarized file
according the specification :

WAP - Wireless Application Protocol /
Binary XML Content Format Specification /
Version 1.3 WBXML (15th May 2000 Approved)

The XML input file must refere to a DTD with a public identifier.

The file WAP/wbrules.xml configures this tool for all known DTD.

WAP Specifications, including Binary XML Content Format (WBXML)
 are available on E<lt>http://www.wapforum.org/E<gt>.

=head1 SEE ALSO

 wbxmld, WAP::SAXDriver::wbxml

=head1 AUTHOR

Francois PERRAD, francois.perrad@gadz.org

=cut
