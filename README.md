BlockingQueue
=============

[![Build Status](https://semaphoreci.com/api/v1/projects/019de5e9-689e-4c1c-b5ba-3242e44ab483/455080/badge.svg)](https://semaphoreci.com/joekain/blockingqueue) [![Inline docs](http://inch-ci.org/github/joekain/BlockingQueue.svg?branch=master)](http://inch-ci.org/github/joekain/BlockingQueue)

BlockingQueue is a simple queue implemented as a GenServer.  It has a fixed
maximum length established when it is created.

The queue is designed to decouple, but limit, the latency between a producer and
consumer.  When pushing to a full queue the `push` operation blocks
preventing the producer from making progress until the consumer catches up.
Likewise, when calling `pop` on an empty queue the call blocks until there
is work to do.

## Installation

Add a dependency in your mix.exs:

{% highlight elixir %}
deps: [{:blocking_queue, "~> 1.0.0"}, ...]
{% endhighlight %}

## Examples

A simple example:

{% highlight elixir %}
{:ok, pid} = BlockingQueue.start_link(5)
BlockingQueue.push(pid, "Hi")
BlockingQueue.pop(pid) # should return "Hi"
{% endhighlight %}

The queue is designed to be used from more complex examples in which the
producer and consumer are in separate processes and run assynchronously to each
other.

## Contribute

Just fork the repo, make your change, and send me a pull request.
