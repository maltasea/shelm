use strict;
use warnings;

my $n = 200000;
my $i = 0;
my $acc = 0;

while ($i < $n) {
  $acc = $acc + (($i * 3) % 97);
  $i = $i + 1;
}

print("$acc\n");
