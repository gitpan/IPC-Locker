#$Id: test.pl,v 1.2 1999/08/23 14:21:42 wsnyder Exp $
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..6\n";
	print "****NOTE****: You need 'lockerd &' running for this test!\n";
    }
END {print "not ok 1\n" unless $loaded;}
use IPC::Locker;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

# 2: Constructor
print (($lock = new IPC::Locker(timeout=>10,
				print_down=>sub { die "%Error: Can't locate lock server\n"
						      . "\tRun 'lockerd &' before this test\n";
					      }
				)) ? "ok 2\n" : "not ok 2\n");

# 3: Lock obtain
print (($lock->lock()) ? "ok 3\n" : "not ok 3\n");

# 4: Lock state
print (($lock->locked()) ? "ok 4\n" : "not ok 4\n");

# 5: Lock owner
print (($lock->owner()) ? "ok 5\n" : "not ok 5\n");

# 6: Lock obtain and fail
print ((!defined( IPC::Locker->lock(block=>0, user=>'alternate') ))
       ? "ok 6\n" : "not ok 6\n");

# 7: Lock release
print (($lock->unlock()) ? "ok 7\n" : "not ok 7\n");

# 8: Destructor
undef $lock;
print "ok 8\n";

