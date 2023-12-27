#!/bin/sh -ex

case $(uname) in
    Darwin)
        sudo=sudo
        zeekpath=/usr/local/zeek
        ;;
    Linux)
        sudo=sudo
        zeekpath=/usr/local/zeek
        ;;
    *_NT-*)
        exe=.exe
        zeekpath=/d/usr/local/zeek
        ;;
    *)
        echo "unknown OS: $(uname)" >&2
        exit 1
        ;;
esac

zkg_meta() {
    section=${1:?'section required'}
    option=${2:?'option required'}
    python3 <<EOF
import configparser
c = configparser.ConfigParser()
c.read('zkg.meta')
print(c.get('$section', '$option', fallback=''))
EOF
}

install_zeek_package() {
    github_repo=${1:?'github_repo required'}
    git_ref=${2:?'git_ref required'}
    package=${github_repo#*/}
    mkdir $package
    (
        export PATH=$zeekpath/bin:$PATH
        cd $package
        curl -sL https://github.com/$github_repo/tarball/$git_ref |
            tar -xzf - --strip-components 1

        script_dir=$(zkg_meta package script_dir)
        $sudo cp -r "$script_dir" $zeekpath/share/zeek/site/$package/

        build_command=$(zkg_meta package build_command)
        if [ "$build_command" ]; then
            if [ "$OS" = Windows_NT ]; then
                export LDFLAGS='-static -Wl,--allow-multiple-definition'
            fi
            sh -c "$build_command"
            $sudo tar -xf build/*.tgz -C $zeekpath/lib/zeek/plugins
        fi

        test_command=$(zkg_meta package test_command)
        if [ "$test_command" ]; then
            # Btest fails without explanation on the GitHub Actions
            # Windows runners, so skip tests there.
            if [ "$GITHUB_ACTIONS" != true -o "$OS" != Windows_NT ]; then
               sh -c "$test_command"
            fi
        fi

        echo "@load $package" | $sudo tee -a $zeekpath/share/zeek/site/local.zeek
    )
    rm -r $package
}

$sudo pip3 install btest wheel

install_zeek_package brimsec/geoip-conn 1d5700319dd52d61273f55b4e15a9d01f29cf4bd
install_zeek_package salesforce/hassh cfa2315257eaa972e86f7fcd694712e0d32762ff
install_zeek_package salesforce/ja3 133f2a128b873f9c40e4e65c2b9dc372a801cf24
echo "@load policy/protocols/conn/community-id-logging" | $sudo tee -a $zeekpath/share/zeek/site/local.zeek

mv zeek zeek-src
mkdir -p zeek/bin zeek/lib/zeek zeek/share/zeek
cp zeekrunner$exe zeek/
cp $zeekpath/bin/zeek$exe zeek/bin/
cp -R $zeekpath/lib/zeek/plugins zeek/lib/zeek/
for d in base policy site builtin-plugins; do
    cp -R $zeekpath/share/zeek/$d zeek/share/zeek/
done
