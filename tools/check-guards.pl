#!/usr/bin/perl
# SPDX-License-Identifier: GPL-3.0-or-later
# Finds calls inside a @try whose @catch can't run on armv7 with this toolchain.
#
# LLVM's SjLj lowering (SjLjEHPrepare.cpp, Instruction::mayThrow) marks an invoke "no landing pad" when all of
# this holds, and the exception then goes straight past the handler:
#   - it isn't in the function's first block;
#   - its landing pad has no catch-all clause (@catch (...), @finally, catch (...));
#   - its landing pad has no cleanup (a local's lifetime, @synchronized, a C++ destructor).
# This applies the same test to the compiler's own output, after inlining and optimization.
#
# usage: check-guards.pl <LLVM IR text>...
#   Theos: make -k -j1 ADDITIONAL_CFLAGS="-S -emit-llvm"   (the .o files are then IR text, and linking fails)
# Prints each such call. Exits 1 if there are any.
use strict;
use warnings;

my ($total, $dead, $read) = (0, 0, 0);

for my $file (@ARGV) {
    open(my $in, '<', $file) or die "$file: $!";
    my @lines = <$in>;
    close($in);
    next unless grep { /^target triple/ } @lines;
    $read++;

    # Selector names, to say which message it was.
    my (%name, %selector);
    for (@lines) {
        $name{$1} = $2 if /^(\@OBJC_METH_VAR_NAME_[\w.]*) = .*c"([^"]*?)(?:\\00)*"/;
        $selector{$1} = $2 if /^(\@OBJC_SELECTOR_REFERENCES_[\w.]*) = .*(\@OBJC_METH_VAR_NAME_[\w.]*)/;
    }

    my ($function, $first, $seen, %pad, @invokes, $label, $lastSelector);
    for my $i (0 .. $#lines) {
        local $_ = $lines[$i];
        if (/^define\b.*?\@("(?:[^"\\]|\\.)*"|[\w.\$-]+)\(/) {
            ($function, $first, $seen, $lastSelector) = ($1, 1, 0, '');
            %pad = ();
            @invokes = ();
            $label = '';
            next;
        }
        next unless defined $function;
        if (/^\}/) {
            for my $call (@invokes) {
                $total++;
                next if $call->{first} || $pad{$call->{unwind}};
                $dead++;
                (my $short = $file) =~ s{.*/}{};
                $short =~ s/\.[0-9a-f]{8}\.o$//;
                print "$short: $function: $call->{callee}\n";
            }
            undef $function;
            next;
        }
        if (/^("?[\w.\$-]+"?):/) {
            $label = $1;
            $first = 0 if $seen;
            next;
        }
        next unless /\S/;
        next if /^\s*;/;
        $seen = 1;
        $lastSelector = $name{$selector{$1}} // $1 if /(\@OBJC_SELECTOR_REFERENCES_[\w.]*)/ && $selector{$1};
        if (/^\s*(?:%\S+ = )?(?:\w+ )*invoke\b/) {
            my $callee = /\@("(?:[^"\\]|\\.)*"|[\w.\$-]+)\(/ ? $1 : 'a function pointer';
            $callee = "[... $lastSelector]" if $callee =~ /^objc_msgSend/ && $lastSelector;
            my $to = $lines[$i + 1] // '';
            my $unwind = "$_ $to" =~ /unwind label %("?[\w.\$-]+"?)/ ? $1 : '';
            push @invokes, { first => $first, unwind => $unwind, callee => $callee };
        }
        if (/= landingpad\b/) {
            $pad{$label} //= 0;
            for (my $j = $i + 1; $j <= $#lines && $lines[$j] =~ /^\s+(cleanup|catch|filter)\b/; $j++) {
                $pad{$label} = 1 if $lines[$j] =~ /^\s+cleanup\b/
                    || $lines[$j] =~ /^\s+catch (?:ptr|i8\*) null\b/
                    || $lines[$j] =~ /^\s+filter \[0 x /;
            }
        }
    }
}
die "No LLVM IR among the files given: did the flags reach the compiler?\n" unless $read;
print "$total calls inside \@try or \@finally, $dead of them can't reach their handler\n";
exit($dead ? 1 : 0);
