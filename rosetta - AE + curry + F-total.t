use 5.010;
use strictures;

use Moo;

use Test::More;
use AnyEvent;
use curry;
BEGIN { $ENV{PERL_FUTURE_STRICT} = 1 }
use AnyEvent::Future;

has count => is => rw => default => 0;

__PACKAGE__->new->run;

sub run {
    my ($self) = @_;

    $|++;

    my $w = AnyEvent->timer    #
      ( after => 0.08, interval => 0.101, cb => sub { print "."; $self->inc } );

    $self->do(1)->get;

    $self->do(2)->get;

    is $self->count, $_, "had $_ events tracked" for 42;
    done_testing;
    return;
}

sub do {
    my ( $self, $id ) = @_;
    return $self->log_to_db("start")    #
      ->then( $self->curry::get_object_name($id) )
      ->then( $self->curry::delete_object )    #
      ->then(
        $self->curry::log_to_db("success"),
        $self->curry::log_to_db("failure"),
      )                                        #
      ->then( $self->curry::finalize );
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

sub finalize {
    my ($self) = @_;
    return $self->log_to_db("done")    #
      ->then(
        sub {
            say "end";
            $self->inc;
            return Future->done;
        }
      );
}

sub call_external_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    my $future = AnyEvent::Future->new;
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
    my $future = AnyEvent::Future->new;
    $self->delay( $future->curry::done );
    return $future;
}

sub delay {
    my ( $self, $cb ) = @_;
    _timer( after => 0.4, cb => $cb );
    return;
}

sub _timer {
    my $cb = pop;
    my $w;
    $w = AnyEvent->timer(
        @_ => sub {
            undef $w;
            $cb->();
            return;
        }
    );
    return;
}
