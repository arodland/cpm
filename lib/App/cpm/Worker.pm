package App::cpm::Worker;
use strict;
use warnings;
use utf8;
our $VERSION = '0.913';

use App::cpm::Worker::Installer;
use App::cpm::Worker::Resolver;
use Config;
use Digest::MD5 ();
use Time::HiRes qw(gettimeofday tv_interval);

sub new {
    my ($class, %option) = @_;
    my $home = $option{home};
    my $logger = $option{logger} || App::cpm::Logger::File->new("$home/build.log.@{[time]}");
    %option = (
        %option,
        logger => $logger,
        base => "$home/work/" . time . ".$$",
        cache => "$home/cache",
        $option{prebuilt} ? (prebuilt_base => $class->prebuilt_base($home)) : (),
    );
    my $installer = App::cpm::Worker::Installer->new(%option);
    my $resolver  = App::cpm::Worker::Resolver->new(%option, impl => $option{resolver});
    bless { %option, installer => $installer, resolver => $resolver }, $class;
}

sub prebuilt_base {
    my ($class, $home) = @_;

    # XXX Taking account of relocatable perls, we also use $Config{startperl}
    my $identity = $Config{startperl} . Config->myconfig;
    my $digest = Digest::MD5::md5_hex($identity);
    $digest = substr $digest, 0, 8;
    "$home/builds/$Config{version}-$Config{archname}-$digest";
}

sub work {
    my ($self, $job) = @_;
    my $type = $job->{type} || "(undef)";
    my $result;
    my $start = $self->{verbose} ? [gettimeofday] : undef;
    if (grep {$type eq $_} qw(fetch configure install)) {
        $result = eval { $self->{installer}->work($job) };
        warn $@ if $@;
    } elsif ($type eq "resolve") {
        $result = eval { $self->{resolver}->work($job) };
        warn $@ if $@;
    } else {
        die "Unknown type: $type\n";
    }
    my $elapsed = $start ? tv_interval($start) : undef;
    $result ||= { ok => 0 };
    $job->merge({%$result, pid => $$, elapsed => $elapsed});
    return $job;
}

1;
