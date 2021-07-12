Table of contents
=================

<!--ts-->
* [Perl Async Rosetta Stone](#perl-async-rosetta-stone)
* [Paradigms](#paradigms)
	* [Pure](#pure)
	* [curry](#curry)
	* [Future](#Future)
	* [Future::AsyncAwait](#futureasyncawait)
* [Comparison Matrices](#comparison-matrices)
	* [iA Upgrades](#ia-upgrades)
	* [AE Upgrades](#ae-upgrades)
	* [Comparison iA to AE](#comparison-ia-to-ae)
<!--te-->

# Perl Async Rosetta Stone

Perl has many async engines, as well as many paradigms of interacting with
asychronous code. This repository attempts to provide translations between
different paradigms, implemented in different engines, and fully runnable.

In order to verify that the code runs correctly on your system, check the repo
out and run prove like so. It should produce output as below and a summary
indicating all tests passed successful.

	$ prove -v .
	./rosetta - AE + curry + F-outer.t .......
	log_to_db, start
	....get_object_name, name 1
	....delete_object, name 1
	....log_to_db, success
	....log_to_db, done
	....end
	log_to_db, start
	....get_object_name, name 2
	....delete_object, name 2
	....log_to_db, failure
	....log_to_db, done
	....end
	ok 1 - had 42 events tracked
	[...]
	Files=10, Tests=10, 42 wallclock secs ( 0.00 usr  0.06 sys +  0.64 cusr  1.02 csys =  1.72 CPU)
	Result: PASS

The currently implemented engines are IO::Async (iA) and AnyEvent (AE). I plan
to add Mojolicious' engine.

At the end of the readme is a list of tables with links to easy diffs of the
implementations.

# Paradigms

These are the paradigms implemented, as well as some discussion of their
implementation details.

## Pure

This is the longest example and the most simple in terms of technique. It's very
similar to how things in Javascript are done, and typically labelled "callback
hell". It's a collection of subs that take callbacks as arguments and wrap them
in callbacks and start work in a non-blocking ways. The wrapped callbacks may
then, when triggered at the end of the non-blocking task, forward the original
callback into further subs doing non-blocking work, or finally execute it.

Some subs take only a single callback, and pass results into it so the callback
can do work on them. Some inspect the generated value directly, take multiple
callbacks and then decide which one to execute in order to make a
success/failure decision.

The return value of these subs is generally not used for anything and as such
they provide none.

	sub do {
		my ( $self, $id, $end_cb ) = @_;
		my $new_end_cb = sub {
			$self->finalize($end_cb);
			return;
		};
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
								$self->log_to_db( "success" => $new_end_cb );
								return;
							},
							sub {
								$self->log_to_db( "failure" => $new_end_cb );
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

## [curry](https://metacpan.org/pod/curry)

curry is a module that doesn't really present a new paradigm, but provides an
extremely concise way of converting `sub { $self->method( $manual, @_ ) }` into
`$self->curry::method($manual)`, which is a lot shorter and still operates in
mostly the same way.

Note: The returns above are all removed with this module on the assumption that
since no return value is used for anything and as such allowing implicit returns
is not harmful.

	sub do {
		my ( $self, $id, $end_cb ) = @_;
		$end_cb = $self->curry::finalize($end_cb);
		$self->log_to_db(
			"start",
			$self->curry::get_object_name(
				$id,
				$self->curry::delete_object(
					$self->curry::log_to_db( "success" => $end_cb ),
					$self->curry::log_to_db( "failure" => $end_cb ),
				),
			),
		);
		return;
	}

## [Future](https://metacpan.org/pod/Future)

Futures (sometimes also called Promises) invert the structure of the pure
technique above. As a reminder, pure technique takes a callback as an argument
and then passes that to a non-blocking task, and returns nothing. Subs using
Futures take no callbacks as arguments. Instead they construct an object, and
pass one of its methods as a callback to the non-blocking task, then return the
object.

This inversion means that instead of nesting callbacks endlessly, you have
linear chains of futures that make it easy to decouple the produced results from
a task from making decisions about it, and even allows making decisions on how
to chain further after the task.

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

There are two ways to upgrade code from the pure technique to Futures:

### Outer Wrapping

The first method is to create wrappers around your asynchronous subs, that
create a future, and pass its method as a callback to the original asychronous
sub and then return the future.

Then other code can continue calling the original sub, and new code can start
using the wrappers in a Future-oriented structure as in the example above.

	sub log_to_db_f {
		my ( $self, $msg ) = @_;
		my $future = AnyEvent::Future->new;
		$self->log_to_db( $msg, $future->curry::done );
		return $future;
	}

### Total Conversion

With this method you convert your asynchronous subs to Future-returning subs
(working outside in), which results in remarkably simple-looking subs.

	sub log_to_db {
		my ( $self, $msg ) = @_;
		return $self->call_internal_api( "log_to_db", $msg );
	}

Instead of having Futures created in wrappers as outside as you can, you then
create the Futures as deep inside your call tree as you can, usually limited
by whatever other asynchronous Perl modules you are using, and their APIs.

	sub call_internal_api {
		my ( $self, $call, $arg ) = @_;
		say "$call, $arg";
		my $future = AnyEvent::Future->new;
		$self->delay( $future->curry::done );
		return $future;
	}

## [Future::AsyncAwait](https://metacpan.org/pod/Future::AsyncAwait)

This is new and ongoing work by Paul Evans (LeoNerd) to implement Mozilla's
[async and await keywords](https://developer.mozilla.org/en-US/docs/Learn/JavaScript/Asynchronous/Async_await)
in Perl. These keywords automatically wrap asynchronous subs in Future-creating
code, and allow such subs to yield control to the event engine to allow other
tasks to work, without aborting the sub. This leads to some of the most
simple-looking code possible here, and allows controlling the flow of events
using Perl's builtin if and eval keywords.

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

# Comparison Matrices

## iA Upgrades

| From -> To |   **iA** |   **iA** |   **iA** |   **iA** |
| --- | :---: | :---: | :---: | :---: |
|          | **curry** | **curry** | **curry** | **curry** |
|          |          | **F-outer** | **F-total** | **F-total** |
|          |          |          |          |   **AA** |
| **iA** | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20iA%20+%20curry.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **iA+curry** |  | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **iA+curry+F-outer** |  |  | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **iA+curry+F-total** |  |  |  | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20-%20rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |

## AE Upgrades

| From -> To |   **AE** |   **AE** |   **AE** |   **AE** |
| --- | :---: | :---: | :---: | :---: |
|          | **curry** | **curry** | **curry** | **curry** |
|          |          | **F-outer** | **F-total** | **F-total** |
|          |          |          |          |   **AA** |
| **AE** | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE.t%20-%20rosetta%20-%20AE%20+%20curry.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **AE+curry** |  | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE%20+%20curry.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE%20+%20curry.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE%20+%20curry.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **AE+curry+F-outer** |  |  | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **AE+curry+F-total** |  |  |  | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |

## Comparison iA to AE

| From -> To |   **AE** |   **AE** |   **AE** |   **AE** |   **AE** |
| --- | :---: | :---: | :---: | :---: | :---: |
|          |          | **curry** | **curry** | **curry** | **curry** |
|          |          |          | **F-outer** | **F-total** | **F-total** |
|          |          |          |          |          |   **AA** |
| **iA** | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20AE.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20AE%20+%20curry.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **iA+curry** | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20AE.t%20.txt) | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20AE%20+%20curry.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **iA+curry+F-outer** | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20AE.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20AE%20+%20curry.t%20.txt) | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-outer.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **iA+curry+F-total** | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20-%20rosetta%20-%20AE.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20-%20rosetta%20-%20AE%20+%20curry.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20.txt) | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |
| **iA+curry+F-total+AA** | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20-%20rosetta%20-%20AE.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20-%20rosetta%20-%20AE%20+%20curry.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-outer.t%20.txt) | [ DIFF ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total.t%20.txt) | [ **DIFF** ](https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/diffs/rosetta%20-%20iA%20+%20curry%20+%20F-total%20+%20AA.t%20-%20rosetta%20-%20AE%20+%20curry%20+%20F-total%20+%20AA.t%20.txt) |