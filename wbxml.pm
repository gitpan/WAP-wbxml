require 5.005;

use strict;
use integer;
use UNIVERSAL;

package WbXml;
use vars qw($VERSION);
$VERSION = '1.02';

=head1 NAME

WAP::wbxml - Binarization of XML file

=head1 SYNOPSIS

  use XML::DOM;
  use WAP::wbxml;

  $parser = new XML::DOM::Parser;
  $doc_xml = $parser->parsefile($infile);

  $rules = WbRules->Load();
  $wbxml = new WbXml($rules,$publicid);
  $output = $wbxml->compile($doc_xml,$encoding);

=head1 DESCRIPTION

This module implements binarisation of XML file according the specification :

WAP - Wireless Application Protocol /
Binary XML Content Format Specification /
Version 1.3 WBXML (15th May 2000 Approved)

The XML input file must refere to a DTD with a public identifier.

The file WAP/wbrules.xml configures this tool for all known DTD.

This module needs Data::Dumper and XML::DOM modules.

WAP Specifications, including Binary XML Content Format (WBXML)
 are available on E<lt>http://www.wapforum.org/E<gt>.

=over 4

=cut

use XML::DOM;

# Global tokens
use constant SWITCH_PAGE  	=> 0x00;
use constant _END			=> 0x01;
use constant ENTITY			=> 0x02;
use constant STR_I			=> 0x03;
use constant LITERAL		=> 0x04;
use constant EXT_I_0		=> 0x40;
use constant EXT_I_1		=> 0x41;
use constant EXT_I_2		=> 0x42;
use constant PI				=> 0x43;
use constant LITERAL_C		=> 0x44;
use constant EXT_T_0		=> 0x80;
use constant EXT_T_1		=> 0x81;
use constant EXT_T_2		=> 0x82;
use constant STR_T			=> 0x83;
use constant LITERAL_A		=> 0x84;
use constant EXT_0			=> 0xC0;
use constant EXT_1			=> 0xC1;
use constant EXT_2			=> 0xC2;
use constant OPAQUE			=> 0xC3;
use constant LITERAL_AC		=> 0xC4;
# Global token masks
use constant NULL			=> 0x00;
use constant HAS_CHILD		=> 0x40;
use constant HAS_ATTR		=> 0x80;

=item new

 $wbxml = new WbXml($rules,$publicid);

Create a instance of WBinarizer for a specified kind of DTD.

If the DTD is not known in the rules, default rules are used.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	my ($rules,$publicid) = @_;
	$self->{publicid} = $publicid;
	$self->{rules} = $rules;
	$self->{rulesApp} = $rules->{App}->{$publicid};
	unless ($self->{rulesApp}) {
	 	$self->{rulesApp} = $rules->{DefaultApp};
		warn "Using default rules.\n";
	}
	$self->{skipDefault} = $self->{rulesApp}->{skipDefault};
	$self->{variableSubs} = $self->{rulesApp}->{variableSubs};
	$self->{tagCodepage} = 0;
	$self->{attrCodepage} = 0;
	return $self;
}

sub compileDatetime {
	my $self = shift;
	my ($content) = @_;
	my $str;
	if ($content =~ /(\d+)-(\d+)-(\d+)T(\d+)\.(\d+)\.(\d+)Z/) {
		my $year  = chr (16 * ($1 / 1000) + (($1 / 100) % 10))
				  . chr (16 * (($1 / 10) % 10) + ($1 % 10));
		my $month = chr (16 * ($2 / 10) + ($2 % 10));
		my $day   = chr (16 * ($3 / 10) + ($3 % 10));
		my $hour  = chr (16 * ($4 / 10) + ($4 % 10));
		my $min   = chr (16 * ($5 / 10) + ($5 % 10));
		my $sec   = chr (16 * ($6 / 10) + ($6 % 10));
		$str  = $year . $month . $day;
		$str .= $hour if (ord $hour or ord $min or ord $sec);
		$str .= $min  if (ord $min or ord $sec);
		$str .= $sec  if (ord $sec);
	} else {
		warn "Validate 'Datetime' error : $content.\n";
		$str = "\x19\x70\x01\x01";
	}
	$self->putb('body',OPAQUE);
	$self->putmb('body',length $str);
	$self->putstr('body',$str);
}

sub compilePreserveStringT {
	my $self = shift;
	my ($str) = @_;
	if (exists $self->{h_str}->{$str}) {
		$self->putmb('body',$self->{h_str}->{$str});
	} else {
		my $pos = length $self->{strtbl};
		$self->{h_str}->{$str} = $pos;
#		print $pos," ",$str,"\n";
		$self->putmb('body',$pos);
		$self->putstr('strtbl',$str);
		$self->putb('strtbl',NULL);
	}
}

sub compilePreserveStringI {
	my $self = shift;
	my ($str) = @_;
	$self->putb('body',STR_I);
	$self->putstr('body',$str);
	$self->putb('body',NULL);
}

sub compileStringI {
	my $self = shift;
	my ($str) = @_;
	$str =~ s/\s+/ /g;
	$self->compilePreserveStringI($str) unless ($str =~ /^\s*$/);
}

sub compileStringIwithVariables {
	my $self = shift;
	my ($str) = @_;
	my $text = '';
	while ($str) {
		for ($str) {
			s/^([^\$]+)//
					and $text .= $1,
					    last;

			s/^\$\$//
					and $text .= '$',
					    last;

			s/^\$([A-Z_a-z][0-9A-Z_a-z]*)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_2),
					    $self->compilePreserveStringT($1),
					    last;

			s/^\$\(\s*([A-Z_a-z][0-9A-Z_a-z]*)\s*\)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_2),
					    $self->compilePreserveStringT($1),
					    last;

			s/^\$\(\s*([A-Z_a-z][0-9A-Z_a-z]*)\s*:\s*escape\s*\)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_0),
					    $self->compilePreserveStringT($1),
					    last;

			s/^\$\(\s*([A-Z_a-z][0-9A-Z_a-z]*)\s*:\s*unesc\s*\)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_1),
					    $self->compilePreserveStringT($1),
					    last;

			s/^\$\(\s*([A-Z_a-z][0-9A-Z_a-z]*)\s*:\s*noesc\s*\)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_2),
					    $self->compilePreserveStringT($1),
					    last;

			s/^\$\(\s*([A-Z_a-z][0-9A-Z_a-z]*)\s*:\s*([Ee]([Ss][Cc][Aa][Pp][Ee])?)\s*\)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_0),
					    $self->compilePreserveStringT($1),
					    warn "deprecated-var : $1:$2\n",
					    last;

			s/^\$\(\s*([A-Z_a-z][0-9A-Z_a-z]*)\s*:\s*([Uu][Nn]([Ee][Ss][Cc])?)\s*\)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_1),
					    $self->compilePreserveStringT($1),
					    warn "deprecated-var : $1:$2\n",
					    last;

			s/^\$\(\s*([A-Z_a-z][0-9A-Z_a-z]*)\s*:\s*([Nn][Oo]([Ee][Ss][Cc])?)\s*\)//
					and $self->compileStringI($text),
					    $text = '',
					    $self->putb('body',EXT_T_2),
					    $self->compilePreserveStringT($1),
					    warn "deprecated-var : $1:$2\n",
					    last;

			warn "Pb with: $str \n";
			return;
		}
	}
	$self->compileStringI($text);
}

sub compileEntity {
	my $self = shift;
	my ($code) = @_;
	$self->putb('body',ENTITY);
	$self->putmb('body',$code);
}

sub compileAttributeExtToken {
	my $self = shift;
	my ($ext_token) = @_;
	my $codepage = $ext_token / 256;
	my $token = $ext_token % 256;
	if ($codepage != $self->{attrCodepage}) {
		$self->putb('body',SWITCH_PAGE);
		$self->putb('body',$codepage);
		$self->{attrCodepage} = $codepage;
	}
	$self->putb('body',$token);
}

sub compileTagExtToken {
	my $self = shift;
	my ($ext_token) = @_;
	my $codepage = $ext_token / 256;
	my $token = $ext_token % 256;
	if ($codepage != $self->{tagCodepage}) {
		$self->putb('body',SWITCH_PAGE);
		$self->putb('body',$codepage);
		$self->{tagCodepage} = $codepage;
	}
	$self->putb('body',$token);
}

sub compileAttributeValues {
	my $self = shift;
	my ($value) = @_;
	my $attr;
	my $start;
	my $end;
	while (1) {
		($attr,$start,$end) = $self->{rulesApp}->getAttrValue($value);
		last unless ($attr);
		$self->compilePreserveStringI($start) if ($start);
		$self->compileAttributeExtToken($attr->{ext_token});
		$value = $end;
	}
	$self->compilePreserveStringI($start);
}

sub compileProcessingInstruction {
	my $self = shift;
	my ($target,$data) = @_;
	$self->putb('body',PI);
	my ($attr_start,$dummy) = $self->{rulesApp}->getAttrStart($target,"");
	if ($attr_start) {
		# well-known attribute name
		$self->compileAttributeExtToken($attr_start->{ext_token});
	} else {
		# unknown attribute name
		$self->putb('body',LITERAL);
		$self->compilePreserveStringT($target);
	}
	if ($data) {
		$self->compileAttributeValues($data);
	}
	$self->putb('body',_END);
}

sub prepareAttribute {
	my $self = shift;
	my ($tagname,$attr) = @_;
	my $attr_name = $attr->getName();
	my $attr_value = $attr->getValue();
	my ($attr_start,$remain) = $self->{rulesApp}->getAttrStart($attr_name,$attr_value);
	if ($attr_start) {
		# well-known attribute name
		my $default_list = $attr_start->{default} || "";
		my $fixed_list = $attr_start->{fixed} || "";
		if (! $remain) {
			return 0 if (index($fixed_list,$tagname) >= 0);
			return 0 if ($self->{skipDefault} and index($default_list,$tagname) >= 0);
		}
	}
	return 1;
}

sub compileAttribute {
	my $self = shift;
	my ($tagname,$attr) = @_;
	my $attr_name = $attr->getName();
	my $attr_value = $attr->getValue();
	my ($attr_start,$remain) = $self->{rulesApp}->getAttrStart($attr_name,$attr_value);
	if ($attr_start) {
		# well-known attribute name
		my $default_list = $attr_start->{default} || "";
		my $fixed_list = $attr_start->{fixed} || "";
		my $validate = $attr_start->{validate} || "";
		my $encoding = $attr_start->{encoding} || "";
		unless ($remain) {
			return if (index($fixed_list,$tagname) >= 0);
			return if ($self->{skipDefault} and index($default_list,$tagname) >= 0);
		}
		$self->compileAttributeExtToken($attr_start->{ext_token});

		if ($encoding eq "iso-8601") {
			$self->compileDatetime($attr_value);
		} else {
			if ($remain ne "") {
				if ($validate eq "length") {
					warn "Validate 'length' error : $remain.\n"
							unless ($remain =~ /^[0-9]+%?$/);
					$self->compilePreserveStringI($remain);
				} else {
					if ($self->{variableSubs} and $validate eq "vdata") {
						if (index($remain,"\$") >= 0) {
							$self->compileStringIwithVariables($remain);
						} else {
							$self->compileAttributeValues($remain);
						}
					} else {
						$self->compileAttributeValues($remain);
					}
				}
			}
		}
	} else {
		# unknown attribute name
		$self->putb('body',LITERAL);
		$self->compilePreserveStringT($attr_name);
		$self->putb('body',STR_T);
		$self->compilePreserveStringT($attr_value);
	}
}

sub compileElement {
	my $self = shift;
	my ($elt,$xml_lang,$xml_space) = @_;
	my $cpl_token = NULL;
	my $tagname = $elt->getNodeName();
	my $attrs = $elt->getAttributes();
	if ($attrs->getLength()) {
		my $attr;
		$attr = $elt->getAttribute("xml:lang");
		$xml_lang = $attr if ($attr);
		$attr = $elt->getAttribute("xml:space");
		$xml_space = $attr if ($attr);
		my $nb = 0;
		for (my $i = 0; $i < $attrs->getLength(); $i ++) {
			my $attr = $attrs->item($i);
			if ($attr->getNodeType() == ATTRIBUTE_NODE) {
				$nb += $self->prepareAttribute($tagname,$attr);
			}
		}
		$cpl_token |= HAS_ATTR if ($nb);
	}
	if ($elt->hasChildNodes()) {
		$cpl_token |= HAS_CHILD;
	}
	my $tag_token = $self->{rulesApp}->getTag($tagname);
	if ($tag_token) {
		# well-known tag name
		$self->compileTagExtToken($cpl_token | $tag_token->{ext_token});
	} else {
		# unknown tag name
		$self->putb('body',$cpl_token | LITERAL);
		$self->compilePreserveStringT($tagname);
	}
	if ($cpl_token & HAS_ATTR) {
		for (my $i = 0; $i < $attrs->getLength(); $i ++) {
			my $attr = $attrs->item($i);
			if ($attr->getNodeType() == ATTRIBUTE_NODE) {
				$self->compileAttribute($tagname,$attr);
			}
		}
		$self->putb('body',_END);
	}
	if ($cpl_token & HAS_CHILD) {
		$self->compileContent($elt->getFirstChild(),$xml_lang,$xml_space);
		$self->putb('body',_END);
	}
}

sub compileContent {
	my $self = shift;
	my ($tag,$xml_lang,$xml_space) = @_;
	for (my $node = $tag;
			$node;
			$node = $node->getNextSibling() ) {
		my $type = $node->getNodeType();
		if		($type == ELEMENT_NODE) {
			$self->compileElement($node,$xml_lang,$xml_space);
		} elsif ($type == TEXT_NODE) {
			my $value = $node->getNodeValue();
			if ($self->{variableSubs}) {
				$self->compileStringIwithVariables($value);
			} else {
				if ($xml_space eq "preserve") {
					$self->compilePreserveStringI($value) unless ($value =~ /^\s*$/);
				} else {
					$self->compileStringI($value);
				}
			}
		} elsif ($type == CDATA_SECTION_NODE) {
			my $value = $node->getNodeValue();
			$self->compilePreserveStringI($value);
		} elsif ($type == COMMENT_NODE) {
			# do nothing
		} elsif ($type == ENTITY_REFERENCE_NODE) {
			warn "entity reference : ",$node->getNodeName();	#
		} elsif ($type == PROCESSING_INSTRUCTION_NODE) {
			my $target = $node->getTarget();
			my $data = $node->getData();
			$self->compileProcessingInstruction($target,$data);
		} else {
			die "unexcepted ElementType in compileContent : $type\n";
		}
	}
}

sub compileBody {
	my $self = shift;
	my ($doc) = @_;
	my $xml_lang = "";
	my $xml_space = $self->{rulesApp}->{xmlSpace};
	for (my $node = $doc->getFirstChild();
			$node;
			$node = $node->getNextSibling() ) {
		my $type = $node->getNodeType();
		if		($type == ELEMENT_NODE) {
			$self->compileElement($node,$xml_lang,$xml_space);
		} elsif ($type == PROCESSING_INSTRUCTION_NODE) {
			my $target = $node->getTarget();
			my $data = $node->getData();
			$self->compileProcessingInstruction($target,$data);
		}
	}
}

sub compileCharSet {
	my $self = shift;
	my ($encoding) = @_;
	if ($encoding) {
		$encoding = uc $encoding;
		if (exists $self->{rules}->{CharacterSets}->{$encoding}) {
			my $charset = $self->{rules}->{CharacterSets}->{$encoding};
			$self->putmb('header',$charset);
		} else {
			$self->putmb('header',0);	# unknown encoding
		}
	} else {
		$self->putmb('header',106);		# UTF-8 : default XML encoding
	}
}

sub compilePublicId {
	my $self = shift;
	if (exists $self->{rules}->{PublicIdentifiers}->{$self->{publicid}}) {
		my $publicid = $self->{rules}->{PublicIdentifiers}->{$self->{publicid}};
		$self->putmb('header',$publicid);
	} else {
		$self->putb('header',NULL);
		my $pos = length $self->{strtbl};	# 0
		$self->{h_str}->{$self->{publicid}} = $pos;
		$self->putmb('header',$pos);
		$self->putstr('strtbl',$self->{publicid});
		$self->putb('strtbl',NULL);
	}
}

sub compileVersion {
	my $self = shift;
	$self->putb('header',$self->{rules}->{version});
}

=item compile

 $output = $wbxml->compile($doc_xml,$encoding);

Compiles a XML document.

=cut

sub compile {
	my $self = shift;
	my ($doc,$encoding) = @_;
	$self->{header} = "";
	$self->{body} = "";
	$self->{strtbl} = "";
	$self->{h_str} = {};
	$self->{tagCodepage} = 0;
	$self->{attrCodepage} = 0;
	$self->compileVersion();
	$self->compilePublicId();
	$self->compileCharSet($encoding);
	$self->compileBody($doc);
	$self->putmb('header',length $self->{strtbl});
	return $self->{header} . $self->{strtbl} . $self->{body};
}

=item outfile

 $filename = $wbxml->outfile($infile);

Builds output filename with the good extension.

=cut

sub outfile {
	my $self = shift;
	my ($infile) = @_;
	my $filename = $infile;
	if ($filename =~ /\.[^\.]+$/) {
		$filename =~ s/\.[^\.]+$/\./;
	} else {
		$filename .= '.';
	}
	$filename .= $self->{rulesApp}->{tokenisedExt};
	return $filename;
}

sub putb {
	my $self = shift;
	my ($str,$val) = @_;
	$self->{$str} = $self->{$str} . chr $val;
}

sub putmb {
	my $self = shift;
	my ($str,$val) = @_;
	my $tmp = chr ($val & 0x7f);
	for ($val >>= 7; $val != 0; $val >>= 7) {
		$tmp = chr (0x80 | ($val & 0x7f)) . $tmp;
	}
	$self->{$str} = $self->{$str} . $tmp;
}

sub putstr {
	my $self = shift;
	my ($str,$val) = @_;
	$self->{$str} = $self->{$str} . $val;
}

package Token;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	my ($token,$codepage) = @_;
	$self->{ext_token} = 256 * hex($codepage) + hex($token);
	return $self;
}

package TagToken;
use vars qw(@ISA);
@ISA = qw(Token);

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my ($token,$name,$codepage) = @_;
	my $self = new Token($token,$codepage);
	bless($self, $class);
	$self->{name} = $name;
	return $self;
}

package AttrStartToken;

use vars qw(@ISA);
@ISA = qw(Token);

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my ($token,$name,$value,$codepage,$default,$fixed,$validate,$encoding) = @_;
	my $self = new Token($token,$codepage);
	bless($self, $class);
	$self->{name} = $name;
	$self->{value} = $value if ($value ne "");
	$self->{default} = $default if ($default ne "");
	$self->{fixed} = $fixed if ($fixed ne "");
	$self->{validate} = $validate if ($validate ne "");
	$self->{encoding} = $encoding if ($encoding ne "");
	return $self;
}

package AttrValueToken;

use vars qw(@ISA);
@ISA = qw(Token);

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my ($token,$value,$codepage) = @_;
	my $self = new Token($token,$codepage);
	bless($self, $class);
	$self->{value} = $value;
	return $self;
}

package WbRulesApp;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	my ($publicid,$use_default,$variable_subs,$textual_ext,$tokenised_ext,$xml_space) = @_;
	$self->{publicid} = $publicid;
	$self->{skipDefault} = $use_default eq "yes";
	$self->{variableSubs} = $variable_subs eq "yes";
	$self->{textualExt} = $textual_ext || "xml";
	$self->{tokenisedExt} = $tokenised_ext || "xmlc";
	$self->{xmlSpace} = $xml_space || "preserve";
	$self->{TagTokens} = [];
	$self->{AttrStartTokens} = [];
	$self->{AttrValueTokens} = [];
	return $self;
}

sub getTag {
	my $self = shift;
	my ($tagname) = @_;
	if ($tagname) {
		foreach (@{$self->{TagTokens}}) {
			if ($tagname eq $_->{name}) {
#				print "Tag $_->{name}.\n";
				return $_;
			}
		}
	}
	return undef;
}

sub getAttrStart {
	my $self = shift;
	my ($name, $value) = @_;
	my $best = undef;
	my $remain = $value;
	if ($name) {
		my $max_len = -1;
		foreach (@{$self->{AttrStartTokens}}) {
			if ($name eq $_->{name}) {
				if (exists $_->{value}) {
					my $attr_value = $_->{value};
					my $len = length $attr_value;
					if ( ($attr_value eq $value) or
						 ($len < length $value and $attr_value eq substr($value,0,$len)) ) {
						if ($len > $max_len) {
							$max_len = $len;
							$best = $_;
						}
					}
				} else {
					if ($max_len == -1) {
						$max_len = 0;
						$best = $_;
					}
				}
			}
		}
		if ($best and $max_len != -1) {
			$remain = substr $remain,$max_len;
#			if (exists $best->{value}) {
#				print "AttrStart : $best->{name} $best->{value}.\n";
#			} else {
#				print "AttrStart : $best->{name}.\n";
#			}
		}
	}
	return ($best,$remain);
}

sub getAttrValue {
	my $self = shift;
	my ($start) = @_;
	my $best = undef;
	my $end = "";
	if ($start ne "") {
		my $max_len = 0;
		my $best_found = length $start;
		foreach (@{$self->{AttrValueTokens}}) {
			my $value = $_->{value};
			if ($value ne "") {
				my $len = length $value;
				my $found = index $start,$value;
				if ($found >= 0) {
					if		($found == $best_found) {
						if ($len > $max_len) {
							$max_len = $len;
							$best = $_;
						}
					} elsif ($found <  $best_found) {
						$best = $_;
						$best_found = $found;
						$max_len = $len;
					}
				}
			}
		}
		if ($best) {
			$end = substr $start,$best_found+$max_len;
			$start = substr $start,0,$best_found;
#			print "AttrValue : $best->{value} ($start,$end).\n";
		}
	}
	return ($best,$start,$end);
}

package WbRules;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	my ($version) = @_;
	if ($version =~ /(\d+)\.(\d+)/) {
		$self->{version} = 16 * ($1 - 1) + $2;
	} else {
		$self->{version} = 0x03;		# WBXML 1.3 : latest known version
	}
	$self->{CharacterSets} = {};
	$self->{PublicIdentifiers} = {};
	$self->{App} = {};
	$self->{DefaultApp} = new WbRulesApp("DEFAULT","","","","","");
	return $self;
}

package constructVisitor;
use XML::DOM;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	my($doc) = @_;
	$self->{doc} = $doc;
	return $self;
}

sub visitwbxml {
	my $self = shift;
	my($parent) = @_;
	my $version = $parent->getAttribute("version");
	$self->{wbrules} = new WbRules($version);
	for (my $node = $parent->getFirstChild();
			$node;
			$node = $node->getNextSibling()	) {
		if ($node->getNodeType() == ELEMENT_NODE) {
			$self->{doc}->visitElement($node,$self);
		}
	}
}

sub visitCharacterSets {
	my $self = shift;
	my($parent) = @_;
	for (my $node = $parent->getFirstChild();
			$node;
			$node = $node->getNextSibling()	) {
		if ($node->getNodeType() == ELEMENT_NODE) {
			$self->{doc}->visitElement($node,$self);
		}
	}
}

sub visitCharacterSet {
	my $self = shift;
	my($node) = @_;
	my $name = $node->getAttribute("name");
	my $MIBenum = $node->getAttribute("MIBenum");		# decimal
	$self->{wbrules}->{CharacterSets}->{$name} = $MIBenum;
}

sub visitPublicIdentifiers {
	my $self = shift;
	my($parent) = @_;
	for (my $node = $parent->getFirstChild();
			$node;
			$node = $node->getNextSibling()	) {
		if ($node->getNodeType() == ELEMENT_NODE) {
			$self->{doc}->visitElement($node,$self);
		}
	}
}

sub visitPublicIdentifier {
	my $self = shift;
	my($node) = @_;
	my $name = $node->getAttribute("name");
	my $value = $node->getAttribute("value");           # hexadecimal
	$self->{wbrules}->{PublicIdentifiers}->{$name} = hex $value;
}

sub visitApp {
	my $self = shift;
	my($parent) = @_;
	my $publicid = $parent->getAttribute("publicid");
	my $use_default = $parent->getAttribute("use-default");
	my $variable_subs = $parent->getAttribute("variable-subs");
	my $textual_ext = $parent->getAttribute("textual-ext");
	my $tokenised_ext = $parent->getAttribute("tokenised-ext");
	my $xml_space = $parent->getAttribute("xml-space");
	my $app = new WbRulesApp($publicid,$use_default,$variable_subs,$textual_ext,$tokenised_ext,$xml_space);
	$self->{wbrules}->{App}->{$publicid} = $app;
	$self->{wbrulesapp} = $app;
	for (my $node = $parent->getFirstChild();
			$node;
			$node = $node->getNextSibling()	) {
		if ($node->getNodeType() == ELEMENT_NODE) {
			$self->{doc}->visitElement($node,$self);
		}
	}
}

sub visitTagTokens {
	my $self = shift;
	my($parent) = @_;
	for (my $node = $parent->getFirstChild();
			$node;
			$node = $node->getNextSibling()	) {
		if ($node->getNodeType() == ELEMENT_NODE) {
			$self->{doc}->visitElement($node,$self);
		}
	}
}

sub visitTAG {
	my $self = shift;
	my($node) = @_;
	my $token = $node->getAttribute("token");
	my $name = $node->getAttribute("name");
	my $codepage = $node->getAttribute("codepage");
	my $tag = new TagToken($token,$name,$codepage);
	push @{$self->{wbrulesapp}->{TagTokens}}, $tag;
}

sub visitAttrStartTokens {
	my $self = shift;
	my($parent) = @_;
	for (my $node = $parent->getFirstChild();
			$node;
			$node = $node->getNextSibling()	) {
		if ($node->getNodeType() == ELEMENT_NODE) {
			$self->{doc}->visitElement($node,$self);
		}
	}
}

sub visitATTRSTART {
	my $self = shift;
	my($node) = @_;
	my $token = $node->getAttribute("token");
	my $name = $node->getAttribute("name");
	my $value = $node->getAttribute("value");
	my $codepage = $node->getAttribute("codepage");
	my $default = $node->getAttribute("default");
	my $fixed = $node->getAttribute("fixed");
	my $validate = $node->getAttribute("validate");
	my $encoding = $node->getAttribute("encoding");
	my $tag = new AttrStartToken($token,$name,$value,$codepage,$default,$fixed,$validate,$encoding);
	push @{$self->{wbrulesapp}->{AttrStartTokens}}, $tag;
}

sub visitAttrValueTokens {
	my $self = shift;
	my($parent) = @_;
	for (my $node = $parent->getFirstChild();
			$node;
			$node = $node->getNextSibling()	) {
		if ($node->getNodeType() == ELEMENT_NODE) {
			$self->{doc}->visitElement($node,$self);
		}
	}
}

sub visitATTRVALUE {
	my $self = shift;
	my($node) = @_;
	my $token = $node->getAttribute("token");
	my $value = $node->getAttribute("value");
	my $codepage = $node->getAttribute("codepage");
	my $tag = new AttrValueToken($token,$value,$codepage);
	push @{$self->{wbrulesapp}->{AttrValueTokens}}, $tag;
}

package doc;
use XML::DOM;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	my ($file) = @_;
	my $parser = new XML::DOM::Parser;
	eval { $self->{doc} = $parser->parsefile($file); };
	die $@ if ($@);
	return undef unless ($self->{doc});
	$self->{root} = $self->{doc}->getDocumentElement();
	return $self;
}

sub visitElement {
	my $self = shift;
	my($node,$visitor) = @_;
	my $name = $node->getNodeName();
	$name =~ s/^wbxml://;
	my $func = 'visit' . $name;
	$visitor->$func($node);
}

package WbRules;

=item Load

 $rules = WbRules->Load();

Loads rules from WAP/wbrules.xml or WAP/wbrules.pl.

WAP/wbrules.pl is a serialized version (Data::Dumper).

WAP/wbrules.xml supplies rules for WAP files, but it could extended to over XML applications.

=cut

sub Load {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $path = $INC{'WAP/wbxml.pm'};
	$path =~ s/wbxml\.pm$//i;
	my $persistance = $path . 'wbrules.pl';
	my $config = $path . 'wbrules.xml';

	my @st_config = stat($config);
	die "can't found original rules ($config).\n" unless (@st_config);
	my @st_persistance = stat($persistance);
	if (@st_persistance) {
		if ($st_config[9] > $st_persistance[9]) {	# mtime
			print "$persistance needs update\n";
			die "can't unlink serialized rules ($persistance).\n"
					unless (unlink $persistance);
		}
	}
	use vars qw($rules);
	do $persistance;
	unless (ref $rules eq 'WbRules') {
		use Data::Dumper;
		print "parse rules\n";
		my $doc = new doc($config);
		if ($doc) {
			my $visitor = new constructVisitor($doc);
			$doc->visitElement($doc->{root},$visitor);
			$rules = $visitor->{wbrules};
			$doc = undef;
			my $d = Data::Dumper->new([$rules], [qw($rules)]);
#			$d->Indent(1);
			$d->Indent(0);
			open PERSISTANCE,"> $persistance";
			print PERSISTANCE $d->Dump();
			close PERSISTANCE;
		} else {
			$WbRules::rules = new WbRules("");
		}
	}
	return $WbRules::rules;
}

=back

=head1 SEE ALSO

 xmlc

=head1 COPYRIGHT

(c) 2000-2001 Francois PERRAD, France. All rights reserved.

This program (WAP::wbxml.pm and the internal DTD of wbrules.xml) is distributed
under the terms of the Artistic Licence.

The WAP Specification are copyrighted by the Wireless Application Protocol Forum Ltd.
See E<lt>http://www.wapforum.org/what/copyright.htmE<gt>.

=head1 AUTHOR

Francois PERRAD E<lt>perrad@besancon.sema.slb.comE<gt>

=cut

1;

