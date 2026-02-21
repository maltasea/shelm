use strict;
use warnings;
use Time::HiRes qw(time);

buoy_host_set("time/now_s", sub { return time(); });
buoy_host_set("time/now_ms", sub { return int(time() * 1000.0); });
buoy_host_set("math/add", sub {
  my ($a, $b) = @_;
  return $a + $b;
});

1;
