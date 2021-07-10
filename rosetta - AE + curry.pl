use 5.010;
use strictures;

use Moo;

use AnyEvent;
use curry;

has cv => is => "rw";

__PACKAGE__->new->run;

sub delay {
    my ($cb) = @_;
    my $w;
    $w = AnyEvent->timer(
        after => 1 => cb => sub {
            undef $w;
            $cb->();
            return;
        }
    );
    return;
}

sub run {
    my ($self) = @_;

    $|++;

    my $w = AnyEvent    #
      ->timer( after => 0.1, interval => 0.25, cb => sub { print "." } );

    $self->do(1);
    $self->cv( AnyEvent->condvar )->recv;

    $self->do(2);
    $self->cv( AnyEvent->condvar )->recv;

    return;
}

sub do {
    my ( $self, $id ) = @_;
    $self->log_to_db(
        "start",
        $self->curry::get_object_name(
            $id,
            $self->curry::delete_object(
                $self->curry::log_to_db( "success" => $self->curry::finalize ),
                $self->curry::log_to_db( "failure" => $self->curry::finalize ),
            )
        )
    );
    return;
}

sub finalize {
    my ( $self, $msg ) = @_;
    $self->log_to_db(
        "done",
        sub {
            say "end";
            $self->cv->send;
            return;
        }
    );
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

sub log_to_db {
    my ( $self, $msg, $cb ) = @_;
    $self->call_internal_api( "log_to_db", $msg, $cb );
    return;
}

sub call_external_api {
    my ( $self, $call, $arg, $cb_succ, $cb_fail ) = @_;
    say "$call, $arg";
    my $cb =
      ( $call eq "delete_object" and $arg eq "name 2" ) ? $cb_fail : $cb_succ;
    delay sub {
        $cb->($arg);
        return;
    };
    return;
}

sub call_internal_api {
    my ( $self, $call, $arg, $cb ) = @_;
    say "$call, $arg";
    delay sub {
        $cb->($arg);
        return;
    };
    return;
}
