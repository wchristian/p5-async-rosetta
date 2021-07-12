use 5.010;
use strictures;

use Moo;

use Test::More;
use AnyEvent;
use curry;
BEGIN { $ENV{PERL_FUTURE_STRICT} = 1 }
use AnyEvent::Future;
use Future::AsyncAwait;

has count => is => rw => default => 0;

await __PACKAGE__->new->run;

async sub run {
    my ($self) = @_;

    $|++;

    my $w = AnyEvent->timer    #
      ( after => 0.08, interval => 0.101, cb => sub { print "."; $self->inc } );

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
    my ( $self, $msg ) = @_;
    await $self->log_to_db("done");
    say "end";
    $self->inc;
    return;
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

sub delay {
    my ( $self, $meth, $arg ) = @_;
    my $f = AnyEvent::Future->new;
    my $w;
    $w = AnyEvent->timer(
        after => 0.4 => cb => sub {
            undef $w;
            $f->$meth($arg);
            return;
        }
    );
    return $f;
}
