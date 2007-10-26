use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'          => 'WAP::wbxml',
    'VERSION_FROM'  => 'lib/WAP/wbxml.pm', # finds $VERSION
    'ABSTRACT'      => 'Binarization of XML file used by Wireless Application Protocol',
    'PREREQ_PM'     => {
                        'XML::DOM'      => '1.25',
                        'I18N::Charset' => '1.15',
                        'Data::Dumper'  => 0,
    },
    'EXE_FILES'     => ['bin/wbxmlc'],
    'AUTHOR'        => "Francois PERRAD (francois.perrad\@gadz.org)",
    'dist'          => {
                        'COMPRESS'      => 'gzip',
                        'SUFFIX'        => '.gz',
    },
);

sub MY::install {
    package MY;
    my $script = shift->SUPER::install(@_);
    $script =~ s/install :: (.*)$/install :: $1 compile_rules/m;
    $script .= <<"INSTALL";

compile_rules :
\twbxmlc samples/personal.xml
\t\$(RM_F) samples/personal.wbxml

INSTALL

    return $script;
}

