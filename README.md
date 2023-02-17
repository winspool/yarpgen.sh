# yarpgen.sh

 Welcome to a script with TAP output to generate testfiles with YARPGen </br>
 and compare the results of a testing c/c++ compiler ( $TESTCC | $TESTCXX ) </br>
 with the results of a reference c/c++ compiler ( $REFCC | $REFCXX ) </br>

 On failure, additional helper scripts for 'creduce' are created.


## Simple Usage
```
 yarpgen.sh [first_seed] [-] [last_seed]
```

 YARPGen is called with a seed value to create reproducible testfiles </br>
 default range for the seed value is 1 - 99 </br>
 (use command line args for other ranges) </br>
 (a single value test the compilers with only one specific testfile)


## Supported environment variable

 * DEBUG           print many extra informations
 * YARPGEN_BIN     use a different YARPGen binary
 * YARPGEN_OPTIONS use additional options for yarpgen
 * RUNTIME_DIR     use this directory as working directory [ $XDG_RUNTIME_DIR/subdir | /tmp/$subdir ]

 * REFCC           c reference compiler  [ \$HOSTCC | \$BUILDCC | $def_refcc ]
 * REFCXX          c++ reference compiler[ \$HOSTCXX | \$BUILDCXX | $def_refcxx ]
 * REFCCFLAGS      extra flags for the c reference compiler
 * REFCXXFLAGS     extra flags for the c++ reference compiler

 * TESTCC          c compiler to test    [ \$CC ]
 * TESTCXX         c++ compiler to test  [ \$CXX ]
 * TESTCCFLAGS     extra flags for the c compiler to test  [ \$CCFLAGS ]
 * TESTCXXFLAGS    extra flags for the c++ compiler to test  [ \$CXXFLAGS ]


As example, when creating testfiles for a 32bit compiler, yarpgen (v1) needs
```
YARPGEN_OPTIONS="-m 32" 
```

## The scriptname can select the versions (yarpgen & std) and the reference compiler (binary & flags)

 The scriptname can also be used to define the yarpgen version and the std mode</br>
 as well as the reference compiler and flags for the reference compiler.</br>
 At the end of the first part (upto the first dot), the underscore can be used to select the std.</br>
 In addition, a number before the underscore can be used select a specific yarpgen version.</br>
 After the ".sh" extension was stripped, the remaining dots are used to split additional options.</br>

 Examples:
```
 * yarpgen.tcc.sh
 * YARPGEN_OPTIONS="-m 32"  yarpgen_c99.owcc.sh
 * YARPGEN_OPTIONS="-m 32"  yarpgen_c11.gcc.-m32.sh
 * yarpgen.clang.--target.x86_64-linux-musl.sh
```
 Example using a renamed yarpgen from the v1 source tree:
```
 * yarpgen1_c99.sh
```


## More details

 Testfiles are created in a subdirectory of XDG_RUNTIME_DIR </b>
 (which is normally a RAM-disc, based on tmpfs). </br>
 This is much faster and avoids write pressure on a physical disc (probably a flash disc).

 When building or running a test binary or comparing the result fails, </br>
 additional shell scripts are created, which can be used to rebuild and run/diff the programs<br>
 A script to be used for reducing failed tests is missing.

 To avoid to fill up the disc, all files for the current seed value are deleted, </br>
 when both compile variants work and running the created programs produced the same result.

 The output of this script is compatible to TAP: Test Anything Protocol
 
 LICENSE: MIT
