use 5.010;
use strictures;

use Moo;

use Test::More;
use IO::Async::Timer::Periodic;
use IO::Async::Loop;

has count => is => rw => default => 0;
has loop  => is => ro => default => sub { IO::Async::Loop->new };

__PACKAGE__->new->run;

sub run {
    my ($self) = @_;

    $|++;

    $self->loop->add($_) for IO::Async::Timer::Periodic    #
      ->new( interval => 0.1, on_tick => sub { print "."; $self->inc } )->start;

    $self->do(1);
    $self->loop->run;

    $self->do(2);
    $self->loop->run;

    is $self->count, $_, "had $_ events tracked" for 42;
    done_testing;
    return;
}

sub do {
    my ( $self, $id ) = @_;
    $self->log_to_db(
        "start",
        sub {
            $self->get_object_name(
                $id,
                sub {
                    my ($name) = @_;

                    $self->delete_object(
                        $name,
                        sub {
                            $self->log_to_db(
                                "success" => sub {
                                    $self->finalize;
                                    return;
                                }
                            );
                            return;
                        },
                        sub {
                            $self->log_to_db(
                                "failure" => sub {
                                    $self->finalize;
                                    return;
                                }
                            );
                            return;
                        },
                    );
                    return;
                }
            );
            return;
        }
    );
    return;
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
    my ( $self, $name, $cb_succ, $cb_fail ) = @_;
    $self->call_external_api( "delete_object", $name, $cb_succ, $cb_fail );
    return;
}

sub finalize {
    my ( $self, $msg ) = @_;
    $self->log_to_db(
        "done",
        sub {
            say "end";
            $self->loop->stop;
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
            $cb->($arg);
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
