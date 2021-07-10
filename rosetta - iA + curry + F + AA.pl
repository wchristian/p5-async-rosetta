use v5.14;
use strictures;

use Moo;

use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use curry;
use Future::AsyncAwait;

has loop => is => ro => default => IO::Async::Loop->curry::new;

await __PACKAGE__->new->run;

sub delay {
    my ( $self, $meth, $arg ) = @_;
    my $future = $self->loop->new_future;
    $self->loop->watch_time( after => 1, code => $future->$meth($arg) );
    return $future;
}

async sub run {
    my ($self) = @_;

    $|++;

    $self->loop->add($_) for IO::Async::Timer::Periodic    #
      ->new( interval => 0.25, on_tick => sub { print "." } )->start;

    await $self->do(1);
    await $self->do(2);

    return;
}

async sub do {
    my ( $self, $id ) = @_;
    await $self->log_to_db("start");
    my $name = await $self->get_object_name($id);
    my $res  = await $self->delete_object($name);
    if ( $res eq "name 1" ) {
        await $self->log_to_db("success");
    }
    else {
        await $self->log_to_db("failure");
    }
    await $self->finalize;
    return;
}

async sub finalize {
    my ( $self, $msg ) = @_;
    await $self->log_to_db("done");
    say "end";
    $self->loop->stop;
    return;
}

sub get_object_name {
    my ( $self, $id ) = @_;
    return $self->call_external_api( "get_object_name", "name $id" );
}

sub delete_object {
    my ( $self, $name ) = @_;
    return $self->call_external_api( "delete_object", $name );
}

sub log_to_db {
    my ( $self, $msg ) = @_;
    return $self->call_internal_api( "log_to_db", $msg );
}

sub call_external_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    return $self->delay( done => $arg );
}

sub call_internal_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    return $self->delay( done => $arg );
}
