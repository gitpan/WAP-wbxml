use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'          => 'WAP::wbxml',
    'VERSION_FROM'  => 'wbxml.pm', # finds $VERSION
    'ABSTRACT'      => 'Binarization of XML file used by Wireless Application Protocol',
    'PREREQ_PM'     => {
                        'XML::DOM'      => '1.25',
                        'Data::Dumper'  => 0,
    },
    'PM'            => {
                        'wbxml.pm'      => '$(INST_LIBDIR)/wbxml.pm',
                        'wbrules.xml'   => '$(INST_LIBDIR)/wbrules.xml',
    },
    'EXE_FILES'     => ['xmlc'],
    'AUTHOR'        => "Francois PERRAD (perrad\@besancon.sema.slb.com)",
    'dist'          => {
                        'COMPRESS'      => 'gzip',
                        'SUFFIX'        => '.gz',
    },
);
