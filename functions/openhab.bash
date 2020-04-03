#!/usr/bin/env bash

openhab2_setup() {
  local openhabVersion
  introtext_stable="You are about to install or upgrade to the latest stable openHAB release.\\n
Please be aware that downgrading from a newer unstable snapshot build is not officially supported. Please consult with the documentation or community forum and be sure to take a full openHAB configuration backup first!"
  successtext_stable="The stable release of openHAB is now installed on your system. Please test the correct behavior of your setup. You might need to adapt your configuration, if available. If you did changes to files below '/var/lib/openhab2' before, they were replaced but you can restore them from backup files next to the originals.
Check the \"openHAB Release Notes\" and the official announcements to learn about additons, fixes and changes."
  introtext_testing="You are about to install or upgrade to the latest milestone (testing) openHAB build. It contains the latest features and is supposed to run stable, but if you experience bugs or incompatibilities, please help enhancing openHAB by posting them on the community forum or by raising a Github issue.\\n
  Please be aware that downgrading from a newer build is not officially supported. Please consult with the documentation or community forum and be sure to take a full openHAB configuration backup first!"
successtext_testing="The testing release of openHAB is now installed on your system. Please test the correct behavior of your setup. You might need to adapt your configuration, if available. If you did changes to files below '/var/lib/openhab2' before, they were replaced but you can restore them from backup files next to the originals.
Check the \"openHAB Release Notes\" and the official announcements to learn about additons, fixes and changes."
  introtext_unstable="Proceed with caution!\\nYou are about to switch over to the latest openHAB 2 unstable snapshot build. The daily snapshot builds contain the latest features and improvements but might also suffer from bugs or incompatibilities. Please be sure to take a full openHAB configuration backup first!"
  successtext_unstable="The latest unstable snapshot build of openHAB 2 is now running on your system. Please test the correct behavior of your setup. You might need to adapt your configuration, if available. If you did changes to files below '/var/lib/openhab2' before, they were replaced but you can restore them from backup files next to the originals.\\nIf you find any problem or bug, please report it and state the snapshot version you are on. To stay up-to-date with improvements and bug fixes you should upgrade your packages (the openhab2 and openhab2-addons packages) regularly."

  if [ "$1" == "unstable" ]; then
    UNSTABLE=1
  fi

  if [ "$1" == "testing" ]; then
    TESTING=1
  fi

  if [ -z "$UNSTABLE" ]; then
    if [ -z "$TESTING" ]; then
      echo -n "$(timestamp) [openHABian] Installing or upgrading to latest openHAB release (stable)... "
      introtext=$introtext_stable
      successtext=$successtext_stable
      REPO="deb https://dl.bintray.com/openhab/apt-repo2 stable main"
    else
      echo -n "$(timestamp) [openHABian] Installing or upgrading to latest openHAB milestone release (testing)... "
      introtext=$introtext_testing
      successtext=$successtext_testing
      REPO="deb https://openhab.jfrog.io/openhab/openhab-linuxpkg testing main"
    fi
  else
    echo -n "$(timestamp) [openHABian] Installing or switching to latest openHAB snapshot (unstable)... "
    introtext=$introtext_unstable
    successtext=$successtext_unstable
    REPO="deb https://openhab.jfrog.io/openhab/openhab-linuxpkg unstable main"
  fi

  if [ -n "$INTERACTIVE" ]; then
    if ! (whiptail --title "openHAB software change, Continue?" --yes-button "Continue" --no-button "Back" --yesno "$introtext" 15 80) then echo "CANCELED"; return 0; fi
  fi

  cond_redirect wget --no-check-certificate -qO - 'https://bintray.com/user/downloadSubjectPublicKey?username=openhab' | apt-key add -

  echo "$REPO" > /etc/apt/sources.list.d/openhab2.list
  cond_redirect apt-get update
  openhabVersion="$(apt-cache madison openhab2 | head -n 1 | cut -d'|' -f2 | xargs)"

  local APT_INST_OPTS="-y --allow-downgrades"
  if is_jessie; then
    # - jessie uses apt 1.0 which does not support --allow-downgrades
    # - ubuntu should be fine starting with xenial (apt v1.2)
    # - no support for other older distros
    APT_INST_OPTS="-y"
  fi
  if ! cond_redirect apt-get ${APT_INST_OPTS} install "openhab2=${openhabVersion}"; then echo "FAILED (apt)"; exit 1; fi
  cond_redirect adduser openhab gpio
  cond_redirect systemctl daemon-reload
  if cond_redirect systemctl enable openhab2.service; then echo "OK"; else echo "FAILED (usr)"; exit 1; fi
  if [ -n "$UNATTENDED" ]; then
    cond_redirect systemctl stop openhab2.service || true
  else
    cond_redirect systemctl restart openhab2.service || true
  fi

  if is_pi || is_pine64; then
    cond_echo "Optimizing Java to run on low memory single board computers... "
    sed -i 's#^EXTRA_JAVA_OPTS=.*#EXTRA_JAVA_OPTS="-Xms250m -Xmx350m"#g' /etc/default/openhab2
  fi

  if [ -n "$INTERACTIVE" ]; then
    whiptail --title "Operation Successful!" --msgbox "$successtext" 15 80
  fi
  dashboard_add_tile openhabiandocs
}

openhab_shell_interfaces() {
  introtext="The openHAB remote console is a powerful tool for every openHAB user. It allows you too have a deeper insight into the internals of your setup. Further details: https://www.openhab.org/docs/administration/console.html
\\nThis routine will bind the console to all interfaces and thereby make it available to other devices in your network. Please provide a secure password for this connection (letters and numbers only! default: habopen):"
  successtext="The openHAB remote console was successfully opened on all interfaces. openHAB has been restarted. You should be able to reach the console via:
\\n'ssh://openhab:<password>@<openhabian-IP> -p 8101'\\n
Please be aware, that the first connection attempt may take a few minutes or may result in a timeout due to key generation."

  echo -n "$(timestamp) [openHABian] Binding the openHAB remote console on all interfaces... "
  if [ -n "$INTERACTIVE" ]; then
    sshPassword=$(whiptail --title "Bind Remote Console, Password?" --inputbox "$introtext" 20 60 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then
      echo "aborted"
      return 0
    fi
  fi
  [[ -z "${sshPassword// }" ]] && sshPassword="habopen"

  cond_redirect sed -i "s/sshHost = 127.0.0.1/sshHost = 0.0.0.0/g" /var/lib/openhab2/etc/org.apache.karaf.shell.cfg
  cond_redirect sed -i "s/openhab = .*,/openhab = $sshPassword,/g" /var/lib/openhab2/etc/users.properties
  cond_redirect systemctl restart openhab2.service

  if [ -n "$INTERACTIVE" ]; then
    whiptail --title "Operation Successful!" --msgbox "$successtext" 15 80
  fi
  echo "OK"
}

vim_openhab_syntax() {
  echo -n "$(timestamp) [openHABian] Adding openHAB syntax to vim editor... "
  # these may go to "/usr/share/vim/vimfiles" ?
  mkdir -p /home/"${username:-openhabian}"/.vim/{ftdetect,syntax}
  cond_redirect wget -O "/home/$username/.vim/syntax/openhab.vim" https://raw.githubusercontent.com/cyberkov/openhab-vim/master/syntax/openhab.vim
  cond_redirect wget -O "/home/$username/.vim/ftdetect/openhab.vim" https://raw.githubusercontent.com/cyberkov/openhab-vim/master/ftdetect/openhab.vim
  chown -R "$username:$username" /home/"$username"/.vim
  echo "OK"
}

nano_openhab_syntax() {
  # add nano syntax highlighting
  echo -n "$(timestamp) [openHABian] Adding openHAB syntax to nano editor... "
  cond_redirect wget -O /usr/share/nano/openhab.nanorc https://raw.githubusercontent.com/airix1/openhabnano/master/openhab.nanorc
  echo -e "\\n## openHAB files\\ninclude \"/usr/share/nano/openhab.nanorc\"" >> /etc/nanorc
  echo "OK"
}

multitail_openhab_scheme() {
  echo -n "$(timestamp) [openHABian] Adding openHAB scheme to multitail... "
  cp "$BASEDIR"/includes/multitail.openhab.conf /etc/multitail.openhab.conf
  sed -i "/^.*multitail.*openhab.*$/d" /etc/multitail.conf
  sed -i "s|# misc|include:/etc/multitail.openhab.conf\\n#\\n# misc|g" /etc/multitail.conf
  echo "OK"
}

openhab_is_installed() {
  dpkg-query -l "openhab2" &>/dev/null
  return $?
}

openhab_is_running() {
  if [ "$(systemctl is-active openhab2)" != "active" ]; then return 1; fi
  if [ -r /etc/default/openhab2 ]; then
  # shellcheck source=/etc/default/openhab2 disable=SC1091
  source /etc/default/openhab2
  fi
  # Read and set openHAB variables set in /etc/default/ scripts
  if [ -z "${OPENHAB_HTTP_PORT}" ];  then OPENHAB_HTTP_PORT=8080; fi
  if [ -z "${OPENHAB_HTTPS_PORT}" ]; then OPENHAB_HTTPS_PORT=8443; fi
  return 0;
}

# create systemd config to enforce delaying rules loading
delayed_rules() {
  local targetdir=/etc/systemd/system/openhab2.service.d

  if [ "$1" == "yes" ]; then
    /bin/mkdir -p $targetdir
    /bin/cp "${BASEDIR}"/includes/systemd-override.conf ${targetdir}/override.conf
  else
    /bin/rm ${targetdir}/override.conf
  fi
  cond_redirect systemctl daemon-reload
  cond_redirect systemctl restart openhab2.service
}

# The function has one non-optinal parameter for the application to create a tile for
dashboard_add_tile() {
  tile_name="$1"
  echo -n "$(timestamp) [openHABian] Adding an openHAB dashboard tile for '$tile_name'... "
  openhab_config_folder="/etc/openhab2"
  dashboard_file="$openhab_config_folder/services/dashboard.cfg"
  case $tile_name in
    grafana|frontail|nodered|find|openhabiandocs)
      true ;;
    *)
      echo "FAILED (tile name not valid)"; return 1 ;;
  esac
  if ! openhab_is_installed || [ ! -d "$openhab_config_folder/services" ]; then
    echo "FAILED (openHAB or config folder missing)"
    return 1
  fi
  touch $dashboard_file
  if grep -q "$tile_name.link" $dashboard_file; then
    echo -n "Replacing... "
    sed -i "/^$tile_name.link.*$/d" $dashboard_file
  fi
  # shellcheck source=includes/dashboard-imagedata.sh disable=SC1091
  source "$BASEDIR/includes/dashboard-imagedata.sh"
  tile_desc=$(eval echo "\$tile_desc_$tile_name")
  tile_url=$(eval echo "\$tile_url_$tile_name")
  tile_imagedata=$(eval echo "\$tile_imagedata_$tile_name")

  if [ -z "$tile_desc" ] || [ -z "$tile_url" ] || [ -z "$tile_imagedata" ]; then
    echo "FAILED (data missing)"
    return 1
  fi

  {
    echo ""
    echo "$tile_name.link-name=$tile_desc"
    echo "$tile_name.link-url=$tile_url"
    echo "$tile_name.link-imageurl=$tile_imagedata"
  } >> $dashboard_file

  echo "OK"
  return 0
}
