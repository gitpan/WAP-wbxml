use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'          => 'WAP::wbxml',
    'VERSION_FROM'  => 'wbxml.pm', # finds $VERSION
    'ABSTRACT'      => 'Binarization of XML file used by Wireless Application Protocol',
    'PREREQ_PM'     => {
                        'XML::DOM'      => '1.25',
                        'I18N::Charset' => '1.15',
                        'Data::Dumper'  => 0,
    },
    'PM'            => {
                        'wbxml.pm'              => '$(INST_LIBDIR)/wbxml.pm',
                        'wap.wbrules.xml'       => '$(INST_LIBDIR)/wap.wbrules.xml',
                        'syncml.wbrules.xml'    => '$(INST_LIBDIR)/syncml.wbrules.xml',
                        'wv.wbrules.xml'        => '$(INST_LIBDIR)/wv.wbrules.xml',
    },
    'EXE_FILES'     => ['wbxmlc.pl'],
    'AUTHOR'        => "Francois PERRAD (francois.perrad\@gadz.org)",
    'dist'          => {
                        'COMPRESS'      => 'gzip',
                        'SUFFIX'        => '.gz',
    },
);
