#!/bin/sh -e

mix compile
mix dialyzer
mix test
MIX_ENV=docs mix inch
