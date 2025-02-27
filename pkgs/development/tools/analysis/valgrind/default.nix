{ lib, stdenv, fetchurl, perl, gdb, cctools, xnu, bootstrap_cmds }:

stdenv.mkDerivation rec {
  pname = "valgrind";
  version = "3.17.0";

  src = fetchurl {
    url = "https://sourceware.org/pub/${pname}/${pname}-${version}.tar.bz2";
    sha256 = "18l5jbk301j3462gipqn9bkfx44mdmwn0pwr73r40gl1irkfqfmd";
  };

  outputs = [ "out" "dev" "man" "doc" ];

  hardeningDisable = [ "stackprotector" ];

  # GDB is needed to provide a sane default for `--db-command'.
  # Perl is needed for `callgrind_{annotate,control}'.
  buildInputs = [ gdb perl ]  ++ lib.optionals (stdenv.isDarwin) [ bootstrap_cmds xnu ];

  # Perl is also a native build input.
  nativeBuildInputs = [ perl ];

  enableParallelBuilding = true;
  separateDebugInfo = stdenv.isLinux;

  preConfigure = lib.optionalString stdenv.isDarwin (
    let OSRELEASE = ''
      $(awk -F '"' '/#define OSRELEASE/{ print $2 }' \
      <${xnu}/Library/Frameworks/Kernel.framework/Headers/libkern/version.h)'';
    in ''
      echo "Don't derive our xnu version using uname -r."
      substituteInPlace configure --replace "uname -r" "echo ${OSRELEASE}"

      # Apple's GCC doesn't recognize `-arch' (as of version 4.2.1, build 5666).
      echo "getting rid of the \`-arch' GCC option..."
      find -name Makefile\* -exec \
        sed -i {} -e's/DARWIN\(.*\)-arch [^ ]\+/DARWIN\1/g' \;

      sed -i coregrind/link_tool_exe_darwin.in \
          -e 's/^my \$archstr = .*/my $archstr = "x86_64";/g'

      substituteInPlace coregrind/m_debuginfo/readmacho.c \
         --replace /usr/bin/dsymutil ${stdenv.cc.bintools.bintools}/bin/dsymutil

      echo "substitute hardcoded /usr/bin/ld with ${cctools}/bin/ld"
      substituteInPlace coregrind/link_tool_exe_darwin.in \
        --replace /usr/bin/ld ${cctools}/bin/ld
    '');

  # To prevent rebuild on linux when moving darwin's postPatch fixes to preConfigure
  postPatch = "";

  configureFlags =
    lib.optional (stdenv.hostPlatform.system == "x86_64-linux" || stdenv.hostPlatform.system == "x86_64-darwin") "--enable-only64bit"
    ++ lib.optional stdenv.hostPlatform.isDarwin "--with-xcodedir=${xnu}/include";

  doCheck = true;

  postInstall = ''
    for i in $out/libexec/valgrind/*.supp; do
      substituteInPlace $i \
        --replace 'obj:/lib' 'obj:*/lib' \
        --replace 'obj:/usr/X11R6/lib' 'obj:*/lib' \
        --replace 'obj:/usr/lib' 'obj:*/lib'
    done
  '';

  meta = {
    homepage = "http://www.valgrind.org/";
    description = "Debugging and profiling tool suite";

    longDescription = ''
      Valgrind is an award-winning instrumentation framework for
      building dynamic analysis tools.  There are Valgrind tools that
      can automatically detect many memory management and threading
      bugs, and profile your programs in detail.  You can also use
      Valgrind to build new tools.
    '';

    license = lib.licenses.gpl2Plus;

    maintainers = [ lib.maintainers.eelco ];
    platforms = lib.platforms.unix;
    badPlatforms = [
      "armv5tel-linux" "armv6l-linux" "armv6m-linux"
      "sparc-linux" "sparc64-linux"
      "riscv32-linux" "riscv64-linux"
      "alpha-linux"
    ];
    broken = stdenv.isDarwin; # https://hydra.nixos.org/build/128521440/nixlog/2
  };
}
