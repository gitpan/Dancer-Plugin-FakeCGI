use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Dancer::Plugin::FakeCGI',
    VERSION_FROM      => 'lib/Dancer/Plugin/FakeCGI.pm', # finds $VERSION
    PREREQ_PM         => {
						'IO::Capture::Stdout' => 0,
						'CGI::Compile' => 0,
						'Test::TinyMocker' => 0,
						}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Dancer/Plugin/FakeCGI.pm', # retrieve abstract from module
       AUTHOR         => 'Kocour EaSy <easy@localdomain>') : ()),
);
