
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "An extension to IPC::Open3 that will feed out and err to callbacks instead of requiring the caller to handle them.",
  "AUTHOR" => "Lucas Theisen <lucastheisen\@pastdev.com>, Alceu Rodrigues de Freitas Junior <arfreitas\@cpan.org>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "IPC-Open3-Callback",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "IPC::Open3::Callback",
  "PREREQ_PM" => {
    "IPC::Open3" => 0
  },
  "TEST_REQUIRES" => {},
  "VERSION" => "1.07",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "IPC::Open3" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



