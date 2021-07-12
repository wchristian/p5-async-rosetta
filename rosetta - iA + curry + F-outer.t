use 5.010;
use strictures;

use Moo;

use Test::More;
use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use curry;

has count => is => rw => default => 0;
has loop  => is => ro => default => IO::Async::Loop->curry::new;

__PACKAGE__->new->run;

sub run {
    my ($self) = @_;

    $|++;

    $self->loop->add($_) for IO::Async::Timer::Periodic    #
      ->new( interval => 0.1, on_tick => sub { print "."; $self->inc } )->start;

    $self->do(1)->get;

    $self->do(2)->get;

    is $self->count, $_, "had $_ events tracked" for 42;
    done_testing;
    return;
}

sub do {
    my ( $self, $id, $end_cb ) = @_;
    return $self->log_to_db_f("start")    #
      ->then( $self->curry::get_object_name_f($id) )
      ->then( $self->curry::delete_object_f )    #
      ->then(
        $self->curry::log_to_db_f("success"),
        $self->curry::log_to_db_f("failure"),
      )                                          #
      ->then( $self->curry::finalize_f );
}

sub inc {
    my ($self) = @_;
    $self->count( $self->count + 1 );
    return;
}

sub log_to_db {
    my ( $self, $msg, $cb ) = @_;
    $self->call_internal_api( "log_to_db", $msg, $cb );
    return;
}

sub get_object_name {
    my ( $self, $id, $cb ) = @_;
    $self->call_external_api( "get_object_name", "name $id", $cb );
    return;
}

sub delete_object {
    my ( $self, $cb_succ, $cb_fail, $name ) = @_;
    $self->call_external_api( "delete_object", $name, $cb_succ, $cb_fail );
    return;
}

sub finalize {
    my ( $self, $end_cb ) = @_;
    $self->log_to_db(
        "done",
        sub {
            say "end";
            $end_cb->();
            $self->inc;
            return;
        }
    );
    return;
}

sub call_external_api {
    my ( $self, $call, $arg, $cb_succ, $cb_fail ) = @_;
    say "$call, $arg";
    my $cb;
    if ( $call eq "delete_object" and $arg eq "name 2" ) {
        $cb = $cb_fail;
    }
    else {
        $cb = $cb_succ;
    }
    $self->delay(
        sub {
            $cb->($arg);
            return;
        }
    );
    return;
}

sub call_internal_api {
    my ( $self, $call, $arg, $cb ) = @_;
    say "$call, $arg";
    $self->delay(
        sub {
            $cb->();
            return;
        }
    );
    return;
}

sub delay {
    my ( $self, $cb ) = @_;
    $self->loop->watch_time( after => 0.4, code => $cb );
    return;
}

sub log_to_db_f {
    my ( $self, $msg ) = @_;
    my $future = $self->loop->new_future;
    $self->log_to_db( $msg, $future->curry::done );
    return $future;
}

sub get_object_name_f {
    my ( $self, $id ) = @_;
    my $future = $self->loop->new_future;
    $self->get_object_name( $id, $future->curry::done );
    return $future;
}

sub delete_object_f {
    my ( $self, $name ) = @_;
    my $future = $self->loop->new_future;
    $self->delete_object( $future->curry::done, $future->curry::fail, $name );
    return $future;
}

sub finalize_f {
    my ($self) = @_;
    my $future = $self->loop->new_future;
    $self->finalize( $future->curry::done );
    return $future;
}
