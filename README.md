# QEMU Aspeed boot tester

Run a test doing a basic boot with network and poweroff for each
Aspeed machines supported in QEMU.

## Supported machines

* `ast2500-evb`
* `ast2600-evb`

## Building

This ``builroot`` tree contains the default configurations for the
Aspeed EVB machines : https://github.com/legoater/buildroot/commits/aspeed

## Run

For all tests, simply run :

```
$ ./aspeed-boot.sh -q --prefix=/path/to/qemu/install/
ast2500-evb : Linux /init login DONE (PASSED)
ast2600-evb : Linux /init net login DONE (PASSED)
```

For a simple machine with a verbose output, run

```
$ ./aspeed-boot.sh --prefix=/path/to/qemu/install/ <machine>
```
