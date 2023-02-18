#!/bin/sh
## Copyright (c) 2023, Detlef Riekenberg
## SPDX-License-Identifier: MIT
##
## a script with TAP output to generate testfiles with yarpge
## and compare the results of a testing c/c++ compiler ( $TESTCC | $TESTCXX )
## with the results of a reference c/c++ compiler ( $REFCC | $REFCXX )
##
## usage: $appname [first_seed] [-] [last_seed]
##
## yarpgen is called with a seed value to create reproducible testfiles
## default range for the seed value: 1 - 99
##  - (use command line args for other ranges)
##  - (a single value generates only one specific test)
##
## supported environment variables:
## DEBUG           print many extra informations
## YARPGEN_BIN     a different yarpgen binary [ $YARPGEN_BIN ]
## YARPGEN_OPTIONS additional options for yarpgen
## RUNTIME_DIR     working directory     [ \$XDG_RUNTIME_DIR/$subdir | /tmp/$subdir ]
##
## REFCC           c reference compiler  [ \$HOSTCC | \$BUILDCC | $def_refcc ]
## REFCXX          c++ reference compiler[ \$HOSTCXX | \$BUILDCXX | $def_refcxx ]
## REFCCFLAGS      extra flags for the c reference compiler
## REFCXXFLAGS     extra flags for the c++ reference compiler
##
## TESTCC          c compiler to test    [ \$CC ]
## TESTCXX         c++ compiler to test  [ \$CXX ]
## TESTCCFLAGS     extra flags for the c compiler to test  [ \$CCFLAGS ]
## TESTCXXFLAGS    extra flags for the c++ compiler to test  [ \$CXXFLAGS ]
##
## As example, when creating testfiles for a 32bit compiler, yarpgen (v1) needs
## YARPGEN_OPTIONS="-m 32"
##
## The scriptname can select the versions (yarpgen & std) and the reference compiler (binary & flags)
##
##  Examples:
##  * yarpgen.tcc.sh
##  * YARPGEN_OPTIONS="-m 32" yarpgen_c99.owcc.sh
##  * YARPGEN_OPTIONS="-m 32" yarpgen_c11.gcc.-m32.sh
##  * yarpgen.clang.--target.x86_64-linux-musl.sh
##
##  Example using yarpgen (v1):
##  * yarpgen1_c99.sh
##
## Testfiles are created in a subdirectory of XDG_RUNTIME_DIR
##
## When building or running a test binary or comparing the result fails,
## additional shell scripts are created, which can be used to rebuild and run/diff the programs
##
## To avoid to fill up the disk, all files for the current seed value are deleted,
## when both compile variants work and running the created programs produced the same result.
##
## The output of this script is compatible to TAP: Test Anything Protocol
##


fullname="`basename "$0" `"
appname="`basename "$0" ".sh"`"
shortname="`echo "$appname" | cut -d "." -f1`"

old_pwd="`pwd`"
my_pid="`echo $$`"

utc_year="`date -u +%Y`"
utc_month="`date -u +%m`"
utc_day="`date -u +%d`"
utc_dayofyear="`date -u +%j`"

debug_me="$DEBUG"

#subdir="$appname_$utc_dayofyear"
#subdir="$appname$my_pid"
#subdir="$appname"
subdir="$shortname"


# range for the yarpgen seed value
id_first="1"
id_last="99"


# "c99" for "-std=c99", "c11" for -std="c11"
# "c++03" for "-std=c++03", "c++11" for "-std=c++11"
def_stdc="c99"
def_cplusplus="c++03"
def_std="$def_stdc"

#file extension for c++ files
cxxext=".cpp"


##
# default options for running the compiler:
# disable all optimizations
def_opt="-O0"
# enable debug infos
def_debug="-g"
# link with the math library
def_libm="-lm"
#disable all warnings
def_warn="-w "
# owcc needs "-Wlevel=0 " to disable warnings
#def_warn="-Wlevel=0 "
# zig cc enables ub-sanitizer by default
#def_warn="-w -fno-sanitize=undefined"
##

def_refcc="gcc"
def_refcxx="g++"

# timeout for running the compiled programm
def_timeout="8"


# all configuration options are above #
#######################################

varpgen_v1=""
yarpgen_set_std=""
compiler_set_std=""

## use c or c++ for c_or_cxx
c_or_cxx=""
std_version=""

# count success / failures
test_id=0
n_fails=0
n_ok=0

## try to detect a reference toolchain from the scriptname
toolchain="`echo "$appname" | cut -d "." -f2`"
toolflags="`echo "$appname" | cut -d "." -f3- | tr "." " " `"

if [ "$toolchain" = "$shortname" ]
then
    toolchain=""
    toolflags=""
fi



# try to detect the yarpgen version from the scriptname
try_as_gen="`echo "$shortname" | cut -d "_" -f1`"
yarpgen_version="`echo "$try_as_gen" | tr -d "+[a-z][A-Z]"`"

if [ -z "$YARPGEN_BIN" ]
then
    YARPGEN_BIN="`echo "$try_as_gen" | tr -d "0123456789"`$yarpgen_version"
fi


if [ -n "$debug_me" ]
then
echo "# appname:      $appname"
echo "# shortname:    $shortname"
echo "# toolchain:    $toolchain"
echo "# toolflags:    $toolflags"
echo "# with yarpgen: $YARPGEN_BIN"
if [ -n "$yarpgen_version" ]
then
echo "# yarpgen ver.: $yarpgen_version"
fi
fi


# try to detect the standard to use from the scriptname
try_as_std="`echo "$shortname" | cut -d "_" -f2`"
if [ "$try_as_std" = "$shortname" ]
then
    try_as_std=""
else
    c_or_cxx="`echo "$try_as_std" | tr -d "0123456789"`"
    std_version="`echo "$try_as_std" | tr -d "+[a-z]"`"
fi


## try to detect our language mode from the environment: c or c++
if [ -z "$c_or_cxx" ]
then
    if [ -n "$REFCC" ]
    then
        c_or_cxx="c"
        REFCXX=""
        REFCXXFLAGS=""
    fi
    if [ -n "$REFCXX" ]
    then
        c_or_cxx="c++"
        REFCC=""
        REFCCFLAGS=""
    fi

    if [ -n "$TESTCC" ]
    then
        c_or_cxx="c"
        TESTCXX=""
        TESTCXXFLAGS=""
    fi

    if [ -n "$TESTCXX" ]
    then
        c_or_cxx="c++"
        TESTCC=""
        TESTCCFLAGS=""
    fi
fi

if [ -z "$c_or_cxx" ]
then
    if [ -n "$CC" ]
    then
        c_or_cxx="c"
    fi
fi

if [ -z "$c_or_cxx" ]
then
    if [ -n "$CXX" ]
    then
    c_or_cxx="c++"
    fi
fi

if [ -z "$c_or_cxx" ]
then
    try_as_std="$def_std"
    c_or_cxx="`echo "$try_as_std" | tr -d "[0-9]"`"
    std_version="`echo "$try_as_std" | tr -d "+[a-z]"`"
fi

###
# when we do not have a std version, use out default
if [ -z "$std_version" ]
then
    if [ "$c_or_cxx" = "c" ]
    then
        try_as_std="$def_stdc"
    else
        try_as_std="$def_cplusplus"
    fi
    c_or_cxx="`echo "$try_as_std" | tr -d "0123456789"`"
    std_version="`echo "$try_as_std" | tr -d "+[a-z]"`"
fi


###
if [ -n "$debug_me" ]
then
    echo "# using std:   $c_or_cxx$std_version"
fi


## We have now a language mode: c or c++ (anything else) and a version
if [ "$c_or_cxx" = "c" ]
then
    srcext=".c"
    compiler_set_std="-std=$c_or_cxx$std_version"

    # yarpgen v1 uses the full version, but yarpgen(master) uses only the language (c/c++)
    if [ -z "$yarpgen_version" ]
    then
        yarpgen_set_std="--std=c"
    else
        yarpgen_set_std="--std=c$std_version"
    fi
else
    srcext="$cxxext"
    compiler_set_std="-std=$c_or_cxx$std_version"
    # yarpgen v1 uses the full version, but yarpgen(master) uses only the language (c/c++)
    if [ -z "$yarpgen_version" ]
    then
        yarpgen_set_std="--std=c++"
    else
        yarpgen_set_std="--std=c++$std_version"
    fi
fi


COMPILER_FLAGS=" $compiler_set_std  $def_debug $def_warn "

# test at least our default optimize flag
if [  -z "$OPTIMIZE" ]
then
    OPTIMIZE="$def_opt"
fi

ref_opt="$def_opt"

# cleanup working directory (default: no cleanup)
cleanup_dir=""


if [ -z "$RUNTIME_DIR" ]
then
    if [ -n "$XDG_RUNTIME_DIR" ]
    then
        RUNTIME_DIR="$XDG_RUNTIME_DIR/$subdir"
    else
        RUNTIME_DIR="/tmp/$subdir"
    fi
    # cleanup our working directory, when everything succeeds
    cleanup_dir="$RUNTIME_DIR"
fi

if [ "$c_or_cxx" = "c" ]
then
    REFCXX=""
    HOSTCXX=""
    BUILDCXX=""
    TESTCXX=""
    CXX=""
    REFCXXFLAGS=""
    HOSTCXXFLAGS=""
    BUILDCXXFLAGS=""
    TESTCXXFLAGS=""
    CXXFLAGS=""

    if [ -z "$REFCC" ]
    then
        if [ -n "$HOSTCC" ]
        then
            REFCC="$HOSTCC"
            REFCCFLAGS="$HOSTCCFLAGS"
        elif [ -n "$BUILDCC" ]
        then
            REFCC="$BUILDCC"
            REFCCFLAGS="$BUILDCCFLAGS"
        fi
    fi

    if [ -z "$REFCC" ]
    then
        REFCC="$toolchain"
    fi
    if [ -z "$REFCC" ]
    then
        REFCC="$def_refcc"
    fi

    if [ -z "$REFCCFLAGS" ]
    then
        REFCCFLAGS="$toolflags"
    fi


    if [ -z "$TESTCC" ]
    then
        TESTCC="$CC"
    fi
    if [ -z "$TESTCCFLAGS" ]
    then
        TESTCCFLAGS="$CFLAGS"
    fi


else

    REFCC=""
    HOSTCC=""
    BUILDCC=""
    TESTCC=""
    CC=""
    REFCCFLAGS=""
    HOSTCCFLAGS=""
    BUILDCCFLAGS=""
    TESTCCFLAGS=""
    CFLAGS=""

    if [ -z "$REFCXX" ]
    then
        if [ -n "$HOSTCXX" ]
        then
            REFCXX="$HOSTCXX"
            REFCXXFLAGS="$HOSTCXXFLAGS"
        elif [ -n "$BUILDCXX" ]
        then
            REFCXX="$BUILDCXX"
            REFCXXFLAGS="$BUILDCXXFLAGS"
        fi
    fi

    if [ -z "$REFCXX" ]
    then
        REFCXX="$toolchain"
    fi
    if [ -z "$REFCXX" ]
    then
        REFCXX="$def_refcxx"
    fi

    if [ -z "$REFCXXFLAGS" ]
    then
        REFCXXFLAGS="$toolflags"
    fi


    if [ -z "$TESTCXX" ]
    then
        TESTCXX="$CXX"
    fi
    if [ -z "$TESTCXXFLAGS" ]
    then
        TESTCXXFLAGS="$CXXFLAGS"
    fi

fi


# A test compiler is always needed
if [ -z "$TESTCC$TESTCXX" ]
then
    echo "No test compiler found"
    exit 1
fi

## parsing command line parameter starts here

n=0
n_last=0



if [ -n "$1" ]
then

    case "$1" in
    "-h" | "--help" | "/?" )
        cat <<HELPTEXT
usage: $fullname [first_seed] [-] [last_seed]

A script with TAP output to generate testfiles with YARPGen
and compare the results of a testing c/c++ compiler ( $TESTCC | $TESTCXX )
with the results of a reference c/c++ compiler ( $REFCC | $REFCXX )

YARPGen is called with a seed value to create reproducible testfiles </br>
default range for the seed value is 1 - 99 </br>
 - (use command line args for other ranges) </br>
 - (a single value test the compilers with only one specific testfile)

Supported environment variables:
DEBUG           print many extra informations
YARPGEN_BIN     a different yarpgen binary [ $YARPGEN_BIN ]
YARPGEN_OPTIONS additional options for running $YARPGEN_BIN
RUNTIME_DIR     working directory     [ \$XDG_RUNTIME_DIR/$subdir | /tmp/$subdir ]

REFCC           c reference compiler  [ \$HOSTCC | \$BUILDCC | $def_refcc ]
REFCXX          c++ reference compiler[ \$HOSTCXX | \$BUILDCXX | $def_refcxx ]
REFCCFLAGS      extra flags for the c reference compiler [ $REFCFLAGS ]
REFCXXFLAGS     extra flags for the c++ reference compiler [ $REFCXXFLAGS ]

TESTCC          c compiler to test    [ \$CC ]
TESTCXX         c++ compiler to test  [ \$CXX ]
TESTCCFLAGS     extra flags for the c compiler to test [ \$CCFLAGS ]
TESTCXXFLAGS    extra flags for the c++ compiler to test [ \$CXXFLAGS ]


The scriptname can also be used to select the versions (for yarpgen & std)
and to select the reference compiler (binary & flags)

Examples:
 * yarpgen.tcc.sh
 * YARPGEN_OPTIONS="-m 32" yarpgen_c99.owcc.sh
 * YARPGEN_OPTIONS="-m 32" yarpgen_c11.gcc.-m32.sh
 * yarpgen.clang.--target.x86_64-linux-musl.sh

Example using yarpgen (v1):
 * yarpgen1_c99.sh

HELPTEXT
        exit 1
        ;;
    * )
        ;;
    esac

    n_first="`echo "$1" | cut -d "-" -f1 `"
    n_last="`echo "$1" | cut -d "-" -f2 `"

    if [ "$1" = "$n_first" ]
    then

        id_first="$n_first"
        if [ -n "$2" ]
        then
            shift
        fi
    else
        if [ -n "$n_first" ]
        then
            id_first="$n_first"
        fi
        if [ -n "$n_last" ]
        then
            id_last="$n_last"
        fi
        shift
    fi

    if [ "$1" = "-" ]
    then
        shift
    fi

    if [ -n "$1" ]
    then
        id_last="$1"
    fi

fi


n=$(($id_first))
n_last=$(($id_last))

if [  $n -lt 0 ]
then
    n=0;
    n_last=$(($id_first * -1))
else
    if [  $n_last -lt 0 ]
    then
        n_last=$(($id_last * -1))
    fi
fi

if [  $n -gt $n_last ]
then
    tmp=$n
    n=$n_last
    n_last=$tmp
fi


echo "# using yarpgen binary:      $YARPGEN_BIN"
if [ -n "$YARPGEN_OPTIONS" ]
then
echo "# using yarpgen options:     $YARPGEN_OPTIONS"
fi
echo "# using yarpgen seed range:  $n to $n_last"
echo "# using working directory:   $RUNTIME_DIR"
echo "# using reference compiler:  $REFCC$REFCXX"
echo "# using reference flags:     $REFCCFLAGS$REFCXXFLAGS"
echo "# using testing compiler:    $TESTCC$TESTCXX"
echo "# using testing flags:       $TESTCCFLAGS$TESTCXXFLAGS"
echo ""


if [  -z "$OPTIMIZE" ]
then
    OPTIMIZE="$def_opt "
fi


mkdir -p "$RUNTIME_DIR"


while [ $n -le $n_last ]
do

    f=0
    this_id="`seq --format=%05.f ${n} ${n} `"
    this_dir="$RUNTIME_DIR/$this_id"
    local_dir="./$this_id"
    cleanup_subdir=""

    latest="$RUNTIME_DIR""/latest"


    rm 2>/dev/null "$RUNTIME_DIR""/driver""$srcext"  "$RUNTIME_DIR""/func""$srcext"  "$RUNTIME_DIR""/info.h"
    rm 2>/dev/null "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"



    if [ -n "$debug_me" ]
    then
        echo "# "$YARPGEN_BIN $yarpgen_set_std $YARPGEN_OPTIONS -s $n --out-dir="$RUNTIME_DIR"  "# for id: $this_id"
    fi
    seed_out="`$YARPGEN_BIN  $yarpgen_set_std $YARPGEN_OPTIONS -s $n  --out-dir="$RUNTIME_DIR" `"

    # output examples:
    # yarpgen_v1: /*SEED 12_123456*/
    # yarpgen:    /*SEED 123456*/
    seed_num="`echo "$seed_out" | cut -d "_" -f 2 | tr -d "SEED/ *"  `"
    seed_id="`seq --format=%05.f ${seed_num} ${seed_num} `"

    need_ref=""
    need_tst=""
    need_diff=""


    if [ -n "$debug_me" ]
    then
        echo "# using seed: $seed_id"
    fi

    if [ -e "$RUNTIME_DIR""/driver""$srcext"  ]
    then
        if [ -n "$debug_me" ]
        then
            echo "# REF  compile: "$REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$RUNTIME_DIR/driver""$srcext" -c  -o "$RUNTIME_DIR""/driver.o"
        fi
        $REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$RUNTIME_DIR/driver""$srcext" -c  -o "$RUNTIME_DIR""/driver.o"
        if [ $? -ne 0 ]
        then
            need_ref="$ref_opt"
        fi


        if [ -n "$debug_me" ]
        then
            echo "# REF  compile: "$REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$RUNTIME_DIR/func""$srcext"   -c  -o "$RUNTIME_DIR""/func.o"
        fi
        $REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$RUNTIME_DIR""/func""$srcext"   -c  -o "$RUNTIME_DIR""/func.o"
        if [ $? -ne 0 ]
        then
            need_ref="$ref_opt"
        fi


        if [ -n "$debug_me" ]
        then
            echo "# REF  link:    "$REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"  -o "$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt
        fi
        $REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"  -o "$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt
        if [ $? -ne 0 ]
        then
            need_ref="$ref_opt"
        fi


        if [ -n "$debug_me" ]
        then
            echo "# REF  run:    ""$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt  >"$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt".txt"
        fi
        timeout  2>/dev/null  $def_timeout "$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt  >"$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt".txt"
        if [ $? -ne 0 ]
        then
            need_ref="$ref_opt"
        fi

    fi

    rm 2>/dev/null "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"

#
# the TST compiler might run in a loop
#

    for tst_opt in $OPTIMIZE
    do
        if [ -n "$debug_me" ]
        then
            echo "# tst  loop for seed $seed_id with $tst_opt"
        fi

        if [ -e "$RUNTIME_DIR""/driver""$srcext"  ]
        then

            if [ -n "$debug_me" ]
            then
                echo "# TST  compile: "$TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$RUNTIME_DIR/driver""$srcext" -c  -o "$RUNTIME_DIR""/driver.o"
            fi
            $TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$RUNTIME_DIR/driver""$srcext" -c  -o "$RUNTIME_DIR""/driver.o"
            if [ $? -ne 0 ]
            then
                need_tst="$tst_opt"
            fi

            if [ -n "$debug_me" ]
            then
                echo "# TST  compile: "$TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$RUNTIME_DIR/func""$srcext"   -c  -o "$RUNTIME_DIR""/func.o"
            fi
            $TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$RUNTIME_DIR/func""$srcext"   -c  -o "$RUNTIME_DIR""/func.o"
            if [ $? -ne 0 ]
            then
                need_tst="$tst_opt"
            fi

            if [ -n "$debug_me" ]
            then
                echo "# TST  link:    "$TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"  -o "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt
            fi
            $TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"  -o "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt
            if [ $? -ne 0 ]
            then
                need_tst="$tst_opt"
            fi

            if [ -n "$debug_me" ]
            then
                echo "# TST   run:    "timeout $def_timeout "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt  >"$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt".txt"

            fi
            timeout $def_timeout "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt  >"$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt".txt"
            if [ $? -ne 0 ]
            then
                need_tst="$tst_opt"
            fi

        fi

#########
# when we have a failure,
# then move files to a subdir and stop
#########

        if [ -e "$RUNTIME_DIR""/driver""$srcext"  ]
        then

            if [ -n "$debug_me" ]
            then
                echo "# chk  diff -u  $RUNTIME_DIR""/""$seed_id""_ref"$ref_opt".txt"  "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt".txt"
            fi

            diff_result="` diff -u  "$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt".txt"  "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt".txt"  `"
            if [ $? -ne 0 ]
            then
                test_id=$(($test_id + 1))
                echo "not ok # diff -u ""$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt".txt"  "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt".txt"
                n_fails=$((n_fails + 1))
                f=$(($f + 16))
                need_diff="$seed_id"

            else
                rm 2>/dev/null  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt".txt"
            fi

        fi


        if [ -e "$RUNTIME_DIR""/driver""$srcext"  ]
        then

            if [ -n "$need_ref" ]
            then

                test_id=$(($test_id + 1))
                echo "not ok # compile REF:"
                echo "       # "  $REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"  -o "$RUNTIME_DIR""/""$seed_id""_ref"$ref_opt
                n_fails=$((n_fails + 1))
                f=$(($f + 1))

            fi


            if [ -n "$need_tst" ]
            then

                test_id=$(($test_id + 1))
                echo "not ok # compile TST:"
                echo "       # $TESTCC$TESTCXX $ref_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS $RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"  -o "$RUNTIME_DIR""/""$seed_id""_tst"$tst_opt
                n_fails=$((n_fails + 1))
                f=$(($f + 2))

            fi


            if [ -n "$need_ref$need_tst$need_diff" ]
            then

                cleanup_dir=""

                mkdir -p "$RUNTIME_DIR""/$seed_id"
                mv 2>/dev/null  "$RUNTIME_DIR""/driver""$srcext"  "$RUNTIME_DIR""/$seed_id""/"
                mv 2>/dev/null  "$RUNTIME_DIR""/func""$srcext"    "$RUNTIME_DIR""/$seed_id""/"
                mv 2>/dev/null  "$RUNTIME_DIR""/init.h"           "$RUNTIME_DIR""/$seed_id""/"

                mv 2>/dev/null  "$RUNTIME_DIR""/$seed_id""_ref"$ref_opt        "$RUNTIME_DIR""/$seed_id""/ref"$ref_opt
                mv 2>/dev/null  "$RUNTIME_DIR""/$seed_id""_ref"$ref_opt".txt"  "$RUNTIME_DIR""/$seed_id""/ref"$ref_opt".txt"
                mv 2>/dev/null  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt        "$RUNTIME_DIR""/$seed_id""/tst"$tst_opt
                mv 2>/dev/null  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt".txt"  "$RUNTIME_DIR""/$seed_id""/tst"$tst_opt".txt"

#                rm 2>/dev/null   "$RUNTIME_DIR""/$seed_id""_ref"$ref_opt  "$RUNTIME_DIR""/$seed_id""_ref"$ref_opt".txt"
#                rm 2>/dev/null  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt".txt"


                echo  >"$RUNTIME_DIR""/$seed_id""/gen.sh" "#!/bin/sh"
                echo >>"$RUNTIME_DIR""/$seed_id""/gen.sh" "$YARPGEN_BIN $yarpgen_set_std $YARPGEN_OPTIONS ""$""YARPGEN_OPTIONS -s $seed_num --out-dir=""./"

                chmod a+x "$RUNTIME_DIR""/$seed_id""/gen.sh"


                echo  >"$RUNTIME_DIR""/$seed_id""/ref$ref_opt"".sh" "#!/bin/sh"
                echo >>"$RUNTIME_DIR""/$seed_id""/ref$ref_opt"".sh" "rm 2>""/dev/null driver.o func.o  ref"$ref_opt  " ref"$ref_opt".txt"
                echo >>"$RUNTIME_DIR""/$seed_id""/ref$ref_opt"".sh" "$REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS \$CFLAGS driver$srcext -c  -o driver.o"
                echo >>"$RUNTIME_DIR""/$seed_id""/ref$ref_opt"".sh" "$REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS \$CFLAGS func$srcext   -c  -o func.o"
                echo >>"$RUNTIME_DIR""/$seed_id""/ref$ref_opt"".sh" "$REFCC$REFCXX $ref_opt $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS \$CFLAGS driver.o   func.o  -o ref"$ref_opt
                if [ -n "$debug_me" ]
                then
                    echo  >>"$RUNTIME_DIR""/$seed_id""/ref$ref_opt"".sh" "size ref"$ref_opt
                fi
                chmod a+x "$RUNTIME_DIR""/$seed_id""/ref$ref_opt"".sh"


                echo  >"$RUNTIME_DIR""/$seed_id""/tst$tst_opt"".sh" "#!/bin/sh"
                echo >>"$RUNTIME_DIR""/$seed_id""/tst$tst_opt"".sh" "rm 2>""/dev/null driver.o func.o  tst"$tst_opt " tst"$tst_opt".txt"
                echo >>"$RUNTIME_DIR""/$seed_id""/tst$tst_opt"".sh" "$TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS \$CFLAGS driver$srcext -c  -o driver.o"
                echo >>"$RUNTIME_DIR""/$seed_id""/tst$tst_opt"".sh" "$TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS \$CFLAGS func$srcext   -c  -o func.o"
                echo >>"$RUNTIME_DIR""/$seed_id""/tst$tst_opt"".sh" "$TESTCC$TESTCXX $tst_opt $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS \$CFLAGS driver.o   func.o  -o tst"$tst_opt
                if [ -n "$debug_me" ]
                then
                    echo  >>"$RUNTIME_DIR""/$seed_id""/tst$tst_opt"".sh" "size tst"$tst_opt
                fi
                chmod a+x "$RUNTIME_DIR""/$seed_id""/tst$tst_opt"".sh"


                echo  >"$RUNTIME_DIR""/$seed_id""/diff$tst_opt"".sh" "#!/bin/sh"
                echo >>"$RUNTIME_DIR""/$seed_id""/diff$tst_opt"".sh" "./ref$ref_opt"".sh"
                echo >>"$RUNTIME_DIR""/$seed_id""/diff$tst_opt"".sh" "./tst$tst_opt"".sh"
                echo >>"$RUNTIME_DIR""/$seed_id""/diff$tst_opt"".sh" "./ref"$ref_opt  ">ref"$ref_opt".txt"
                echo >>"$RUNTIME_DIR""/$seed_id""/diff$tst_opt"".sh" "./tst"$tst_opt  ">tst"$tst_opt".txt"
                echo >>"$RUNTIME_DIR""/$seed_id""/diff$tst_opt"".sh" "diff -u  ref"$ref_opt".txt  tst"$tst_opt".txt"

                chmod a+x  "$RUNTIME_DIR""/$seed_id""/diff$tst_opt"".sh"

            fi



        fi
        rm 2>/dev/null "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"

    done

    if [ -z "$need_ref$need_tst$need_diff" ]
    then

        test_id=$(($test_id + 1))
        echo "ok     # for seed $seed_id with OPTIMIZE: $OPTIMIZE"
        n_ok=$((n_ok + 1))

    fi

    rm  2>/dev/null  "$RUNTIME_DIR""/driver""$srcext"  "$RUNTIME_DIR""/func""$srcext" "$RUNTIME_DIR""/init.h"
    rm  2>/dev/null  "$RUNTIME_DIR""/driver.o"  "$RUNTIME_DIR""/func.o"

    rm  2>/dev/null  "$RUNTIME_DIR""/$seed_id""_ref"$ref_opt  "$RUNTIME_DIR""/$seed_id""_ref"$ref_opt".txt"
    rm  2>/dev/null  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt  "$RUNTIME_DIR""/$seed_id""_tst"$tst_opt".txt"

    n=$((n + 1))

    if [ -n "$debug_me" ]
    then
        echo ""
    fi

done


if [ -n "$cleanup_dir" ]
then
    rm 2>/dev/null -d "$cleanup_dir"
fi

# print a summary
if [ $n_ok -ne 1 ]
then
    echo "# $n_ok tests succeeded"
else
    echo "# 1 test succeeded"
fi

if [ $n_fails -ne 1 ]
then
    echo "# $n_fails tests failed"
else
    echo "# 1 test failed"
fi


if [ $n_fails -eq 0 ]
then
    echo "# All OK"
fi

echo "1..$test_id"

#########################

