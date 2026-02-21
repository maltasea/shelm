use strict;
use warnings;

my $limit = 20000;
my $i = 2;
my $count = 0;

while ($i <= $limit) {
  my $j = 2;
  my $is_prime = 1;

  while (($j * $j) <= $i) {
    if (($i % $j) == 0) {
      $is_prime = 0;
      $j = $i;
    }
    $j = $j + 1;
  }

  if ($is_prime) {
    $count = $count + 1;
  }

  $i = $i + 1;
}

print("$count\n");
