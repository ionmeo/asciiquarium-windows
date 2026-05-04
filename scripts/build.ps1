#!/usr/bin/env pwsh
# Build asciiquarium.exe on Windows

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7+. You are running PowerShell $($PSVersionTable.PSVersion)."
    exit 1
}

if (-not (Test-Path strawberry-perl)) {
    Write-Host "Downloading Strawberry Perl portable..." -ForegroundColor Green
    Invoke-WebRequest -Uri 'https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54221_64bit/strawberry-perl-5.42.2.1-64bit-portable.zip' -OutFile strawberry-perl.zip
    Expand-Archive -Path strawberry-perl.zip -DestinationPath strawberry-perl
    Remove-Item strawberry-perl.zip
}

Write-Host "Adding Strawberry Perl to PATH... (for this session only)" -ForegroundColor Green
$env:PATH = "$PWD\strawberry-perl\perl\bin;$PWD\strawberry-perl\c\bin;$env:PATH"

if (-not (Test-Path PDCurses\wincon\pdcurses.a)) {
    Write-Host "Cloning and building PDCurses..." -ForegroundColor Green
    if (-not (Test-Path PDCurses)) {
        git clone https://github.com/wmcbrine/PDCurses
    }
    Push-Location PDCurses\wincon
    make -f Makefile
    Pop-Location
}

Write-Host "Copying PDCurses headers and library into Strawberry Perl..." -ForegroundColor Green
cp PDCurses/curses.h    strawberry-perl/c/include/curses.h
cp PDCurses/curspriv.h  strawberry-perl/c/include/curspriv.h
cp PDCurses/panel.h     strawberry-perl/c/include/panel.h
cp PDCurses/wincon/pdcurses.a strawberry-perl/c/lib/libpdcurses.a

perl -e "use Curses; 1" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing Term::Animation... (first pass; failure expected)" -ForegroundColor Green
    cpanm Term::Animation

    Write-Host "Patching Makefile of Curses-1.46..." -ForegroundColor Green
    $cursesDir = (Get-Item strawberry-perl/data/.cpanm/work/*/Curses-* |
                  Where-Object PSIsContainer |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1).FullName
    $lines = Get-Content "$cursesDir\Makefile"
    $out = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # OTHERLDFLAGS =   ->   OTHERLDFLAGS = -lpdcurses
        if ($line -match '^OTHERLDFLAGS\s*=\s*$') {
            $out += 'OTHERLDFLAGS = -lpdcurses'
        }
        # \t./makeConfig  >$@   ->   \t$(PERL) makeConfig  >$@
        elseif ($line -match '^\t\./makeConfig') {
            $out += $line.Replace('./makeConfig', '$(PERL) makeConfig')
        }
        # 6-line CC='$(CC)' \ ... $(PERL) testsyms $(TESTSYMS_OPTS)   ->   single `set ...&& ` line
        elseif ($line -eq "`tCC='`$(CC)' \") {
            $out += "`tset CC=`$(CC)&& set INC=-I.&& set CCFLAGS=`$(CCFLAGS)&& set LDLOADLIBS=-lpdcurses `$(LDLOADLIBS)&& set LDDLFLAGS=`$(LDDLFLAGS)&& `$(PERL) testsyms `$(TESTSYMS_OPTS)"
            $i += 5
        }
        else {
            $out += $line
        }
    }
    Set-Content "$cursesDir\Makefile" $out

    Write-Host "Building and installing Curses..." -ForegroundColor Green
    Push-Location $cursesDir
    gmake
    gmake install
    Pop-Location
}

Write-Host "Installing neccessary libraries..." -ForegroundColor Green
cpanm Term::Animation
cpanm PAR::Packer

Write-Host "Creating asciiquarium.exe..." -ForegroundColor Green
pp -o asciiquarium.exe "$PSScriptRoot\..\asciiquarium"

Write-Host ""
Write-Host "Done." -ForegroundColor Green
