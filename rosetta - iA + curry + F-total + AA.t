use v5.14;
use strictures;

use Moo;

use Test::More;
BEGIN { $ENV{PERL_FUTURE_STRICT} = 1 }
use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use curry;
use Future::AsyncAwait;

has count => is => rw => default => 0;
has loop  => is => ro => default => IO::Async::Loop->curry::new;

await __PACKAGE__->new->run;

async sub run {
    my ($self) = @_;

    $|++;

    $self->loop->add($_) for IO::Async::Timer::Periodic    #
      ->new( interval => 0.1, on_tick => sub { print "."; $self->inc } )->start;

    await $self->do(1);

    await $self->do(2);

    is $self->count, $_, "had $_ events tracked" for 42;
    done_testing;
    return;
}

async sub do {
    my ( $self, $id ) = @_;
    await $self->log_to_db("start");
    my $name = await $self->get_object_name($id);
    eval {
        await $self->delete_object($name);
        await $self->log_to_db("success");
    };
    await $self->log_to_db("failure") if $@;
    await $self->finalize;
    return;
}

sub inc {
    my ($self) = @_;
    $self->count( $self->count + 1 );
    return;
}

sub log_to_db {
    my ( $self, $msg ) = @_;
    return $self->call_internal_api( "log_to_db", $msg );
}

sub get_object_name {
    my ( $self, $id ) = @_;
    return $self->call_external_api( "get_object_name", "name $id" );
}

sub delete_object {
    my ( $self, $name ) = @_;
    return $self->call_external_api( "delete_object", $name );
}

async sub finalize {
    my ($self) = @_;
    await $self->log_to_db("done");
    say "end";
    $self->inc;
    return;
}

sub call_external_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    my $future = $self->loop->new_future;
    my $cb;
    if ( $call eq "delete_object" and $arg eq "name 2" ) {
        $cb = $future->curry::fail($arg);
    }
    else {
        $cb = $future->curry::done($arg);
    }
    $self->delay($cb);
    return $future;
}

sub call_internal_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    my $future = $self->loop->new_future;
    $self->delay( $future->curry::done );
    return $future;
}

sub delay {
    my ( $self, $cb ) = @_;
    $self->loop->watch_time( after => 0.4, code => $cb );
    return;
}
