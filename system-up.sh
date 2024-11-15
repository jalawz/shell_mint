#!/bin/bash

if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ -z "$ID" ]; then
    echo "Não foi possível detectar a distribuição."
    exit 1
  fi
  DISTRO=$ID
else
  echo "Distribuição não reconhecida."
  exit 1
fi


# Variáveis
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CUSTOM_FOLDER="$SCRIPT_DIR/resources"
zip_file="ubuntu-desktop-settings.zip"
settings_conf="Downloads/ubuntu-desktop-settings.conf"
update_cmd="sudo apt update -y"
dist_upgrade="sudo apt dist-upgrade -y"
install_cmd="sudo apt install -y"
remove_cmd="sudo apt remove -y"
chrome_url="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
vscode_url="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"

flatpak_apps_optional=(
  io.github.getnf.embellish
  com.rtosta.zapzap
  com.obsproject.Studio
  org.duckstation.DuckStation
  org.ppsspp.PPSSPP
  com.heroicgameslauncher.hgl
  net.lutris.Lutris
  net.pcsx2.PCSX2
  com.discordapp.Discord
  org.telegram.desktop
  com.getpostman.Postman
  io.dbeaver.DBeaverCommunity
  com.jetbrains.PyCharm-Community
  com.jetbrains.IntelliJ-IDEA-Community
  org.gnome.meld
  io.httpie.Httpie
  page.kramo.Sly
  com.github.jeromerobert.pdfarranger
  com.zettlr.Zettlr
)

install_flatpaks() {
  local flatpak_apps=("$@")

  # Ativação do suporte ao Flatpak e AppImage
  if [ "$DISTRO" == "ubuntu" ]; then
    $install_cmd gnome-software gnome-software-plugin-flatpak flatpak libfuse2 -y
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi

  for app in "${flatpak_apps[@]}"; do
    echo "Instalando $app:"
    flatpak install flathub "$app" -y
  done

  flatpak update -y

  sudo flatpak override --filesystem=$HOME/.themes
  sudo flatpak override --filesystem=$HOME/.local/share/icons
}

configure_grub() {
  # Caminho do arquivo de configuração do GRUB
  grub_config="/etc/default/grub"
  if [[ -f "$grub_config" ]]; then
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_config"; then
      sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi_backlight=native"/' "$grub_config"
    else
      echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi_backlight=native"' | sudo tee -a "$grub_config" >/dev/null
    fi
    
    # Determina o comando correto para atualizar o GRUB com base na distribuição
    if grep -qi fedora /etc/os-release; then
      sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    else
      sudo update-grub
    fi
    
    echo "Configuração do GRUB atualizada com sucesso."
  else
    echo "Arquivo de configuração do GRUB não encontrado em $grub_config."
  fi
}

install_docker() {
	echo "Removendo pacotes Docker em distribuição baseada em Ubuntu..."
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    eval "$remove_cmd" $pkg
  done
  # Adiciona o repositório para Linux Mint
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  eval "$update_cmd"
  eval $install_cmd docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo groupadd docker
  sudo usermod -aG docker "$USER"
}

install_zsh() {
  echo "Instalando Zsh..."
  eval $install_cmd zsh util-linux

  echo "Instalando Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  echo "Zsh e Oh My Zsh instalados com sucesso."
}

install_custom_package() {
  local download_path="/tmp/package_latest.deb"
  echo "Baixando e instalando o pacote (versão .deb) para $DISTRO..."
  wget -O "$download_path" "$pacote_url"
  sudo dpkg -i "$download_path"
  sudo apt-get -f install -y

  # Verifica se a instalação foi bem-sucedida
  if [[ $? -eq 0 ]]; then
      echo "Pacote instalado com sucesso! $pacote_url"
      echo "Apagando arquivo baixado..."
      rm "$download_path"
  else
      echo "Erro na instalação do pacote."
  fi
}

install_dev_dependencies() {
  # Instalação do SDKMAN, NVM, pip3, e configuração do virtualenvwrapper
  curl -s "https://get.sdkman.io" | bash
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
  sudo pip3 install virtualenvwrapper --break-system-packages

  # Configuração do virtualenvwrapper no .zshrc
  commands="
  export WORKON_HOME=\$HOME/.virtualenvs
  export VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3
  export VIRTUALENVWRAPPER_VIRTUALENV_ARGS=' -p /usr/bin/python3 '
  export PROJECT_HOME=\$HOME/Devel
  source /usr/local/bin/virtualenvwrapper.sh
  "

  # Verifica se o arquivo .zshrc existe
  if [ -f "$HOME/.zshrc" ]; then
      # Verifica se a linha já está no .zshrc
      if ! grep -q "export WORKON_HOME=\$HOME/.virtualenvs" "$HOME/.zshrc"; then
          echo "$commands" >> "$HOME/.zshrc"
          echo "Comandos adicionados ao final do arquivo ~/.zshrc com sucesso."
      fi
  else
      # Se .zshrc não existir, verifica se o .bashrc existe
      if [ -f "$HOME/.bashrc" ]; then
          if ! grep -q "export WORKON_HOME=\$HOME/.virtualenvs" "$HOME/.bashrc"; then
              echo "$commands" >> "$HOME/.bashrc"
              echo "Comandos adicionados ao final do arquivo ~/.bashrc com sucesso."
          fi
      else
          echo "Nenhum arquivo de configuração (.zshrc ou .bashrc) foi encontrado!"
      fi
  fi
}

install_dependencies() {
  eval $update_cmd
  configure_grub
  install_custom_package $chrome_url
  install_custom_package $vscode_url

  # GIT
  echo "Instalando e configurando GIT"
  eval $install_cmd git
  git config --global user.name "Paulo Roberto Menezes"
  git config --global user.email paulomenezes.web@gmail.com
  git config --global init.defaultBranch main
  # CURL
  echo "Instalando CURL"
  eval $install_cmd curl
  # PIP
  echo "Instalando pip3"
  eval $install_cmd python3-pip
  # DOCKER
  echo "Instalando Docker Engine"
  install_docker
}

custom_mint_orchis() {
  # Setup Inicial
  eval "$update_cmd && $dist_upgrade"

  # Verificar e instalar dependências
  if ! command -v git &> /dev/null; then
    echo "Erro: git não está instalado. Instalando..."
    eval $install_cmd git
  fi

  # Instalar o Nautilus e extensões
  eval $install_cmd nautilus nautilus-admin nautilus-extension-gnome-terminal

  # Configuração de File manager preferido
  gsettings set org.cinnamon.desktop.default-applications.filemanager exec 'nautilus'
  
  # Clonar e instalar o GTK Theme
  git clone https://github.com/vinceliuice/Orchis-theme.git
  cd Orchis-theme
  ./install.sh -t all -c light dark -s compact
  cd ..

  # Instalar Tema de Ícones
  git clone https://github.com/vinceliuice/Tela-circle-icon-theme.git
  cd Tela-circle-icon-theme
  ./install.sh -a
  cd ..

  # Instalar fontes e wallpapers
  sudo unzip -o resources/fonts.zip -d ~/.local/share/
  sudo unzip -o resources/wallpaper.zip -d /usr/share/backgrounds/

  # Instalar e configurar Applets do Cinnamon
  unzip -o resources/cinnamon-applets.zip -d ~/.local/share/cinnamon/applets/
  unzip -o resources/cinnamon-applets-config.zip -d ~/.config/

  # Restaurar a configuração do Cinnamon
  unzip -o resources/orchis/cinnamon-orchis-dconf.zip -d ~/Downloads/
  dconf load / < ~/Downloads/cinnamon-orchis.conf

  # Instalar o ULauncher
  sudo add-apt-repository universe -y
  sudo add-apt-repository ppa:agornostal/ulauncher -y
  eval $update_cmd && $install_cmd ulauncher
  unzip -o resources/ulauncher-themes.zip -d $HOME/.config/

  # Instalar e configurar o Conky
  eval $install_cmd conky-all jq curl playerctl
  unzip -o resources/conky-config.zip -d $HOME

  # Instalar Glava
  eval $install_cmd libgl1-mesa-dev libpulse0 libpulse-dev libxext6 libxext-dev libxrender-dev \
    libxcomposite-dev liblua5.3-dev liblua5.3-0 lua-lgi lua-filesystem libobs0t64 libobs-dev \
    meson build-essential gcc

  sudo ldconfig

  git clone https://gitlab.com/wild-turtles-publicly-release/glava/glava.git
  cd glava
  meson build --prefix /usr
  ninja -C build
  sudo ninja -C build install
  glava --copy-config
  cd ..
  unzip -o resources/glava-config.zip -d $HOME

  # Instalar Plymouth e aplicar o tema
  eval $install_cmd plymouth
  unzip -o resources/plymouth-theme.zip -d /usr/share/plymouth/themes
  sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
    default.plymouth /usr/share/plymouth/themes/spinner_alt/spinner_alt.plymouth 100
  sudo update-alternatives --config default.plymouth
  sudo update-initramfs -u

  echo "Customização finalizada. Para aplicar todas as mudanças, reinicie seu computador."
}

additional_customization_orchis() {
  # Instalar Cava Audio Visualizer
  eval $install_cmd cava
  unzip -o resources/cava-config.zip -d $HOME/.config/

  # Instalar ZSH, oh-my-zsh and powerlevel10k
  install_zsh
  git clone --depth=1 \
  https://github.com/romkatv/powerlevel10k.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
  unzip -o resources/omz-config.zip -d $HOME
  
  # Instalar Color Scheme for Gnome Terminal
  wget -O gogh https://git.io/vQgMr && chmod +x gogh && ./gogh && rm gogh
  dconf load /org/gnome/terminal/ < org.gnome.terminal.dconf

  # Instalar firefox theme
  git clone https://github.com/vinceliuice/WhiteSur-firefox-theme.git
  cd WhiteSur-firefox-theme
  ./install.sh -m
  cd ..

  # Instalar NeoFetch
  eval $install_cmd neofetch
  unzip -o resources/neofetch-config.zip -d $HOME/.config/

  # Change Margin Grouped Window List Applets
  unzip -o resources/mod-cinnamon-css-grouped-window-list.zip -d $HOME/Downloads
  cd $HOME/Downloads
  chmod +x mod-cinnamon-css-grouped-window-list.sh
  ./mod-cinnamon-css-grouped-window-list.sh
  cd $SCRIPT_DIR

}

custom_mint_orchis