use 5.010;
use strictures;

use Moo;

use Test::More;
use AnyEvent;
use curry;
use AnyEvent::Future;

has count => is => rw => default => 0;

__PACKAGE__->new->run;

sub inc {
    my ($self) = @_;
    $self->count( $self->count + 1 );
    return;
}

sub delay {
    my ( $meth, $arg ) = @_;
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

sub run {
    my ($self) = @_;

    $|++;

    my $w = AnyEvent->timer    #
      ( after => 0.08, interval => 0.1, cb => sub { print "."; $self->inc } );

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
      ->then                                   #
      ( $self->curry::log_to_db("success"), $self->curry::log_to_db("failure") )
      ->then( $self->curry::finalize );
}

sub finalize {
    my ( $self, $msg ) = @_;
    return $self->log_to_db("done")            #
      ->then(
        sub {
            say "end";
            $self->inc;
            return;
        }
      );
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
    my $meth;
    if ( $call eq "delete_object" and $arg eq "name 2" ) {
        $meth = "fail";
    }
    else {
        $meth = "done";
    }
    return delay $meth => $arg;
}

sub call_internal_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    return delay done => $arg;
}
