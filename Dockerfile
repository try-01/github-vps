# Menggunakan Ubuntu 22.04 LTS sebagai base image
FROM ubuntu:22.04

# Argumen untuk kredensial dan konfigurasi, termasuk untuk Ngrok
ARG VNC_PASSWORD
ARG USERNAME
ARG USER_PASSWORD
ARG NGROK_TOKEN
ARG REGION=ap # Default region untuk ngrok, bisa diubah. Contoh: us, eu, au, in

# Mengatur frontend DEBIAN agar tidak ada prompt interaktif saat instalasi
ENV DEBIAN_FRONTEND=noninteractive

# 1. Update & Install dependensi yang dibutuhkan
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    xfce4 xfce4-goodies \
    tightvncserver \
    firefox \
    wget unzip curl python3 \
    openssh-server \
    dbus-x11 \
    sudo \
    procps

# 2. Install ngrok
RUN curl -L https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -o /ngrok.tgz && \
    tar xvzf /ngrok.tgz -C /usr/local/bin && \
    chmod +x /usr/local/bin/ngrok && \
    rm /ngrok.tgz

# 3. Setup DBus (diperlukan untuk sesi XFCE)
RUN dbus-uuidgen > /var/lib/dbus/machine-id

# 4. Membuat pengguna non-root
RUN useradd -m -s /bin/bash ${USERNAME} && \
    echo "${USERNAME}:${USER_PASSWORD}" | chpasswd && \
    adduser ${USERNAME} sudo

# 5. Setup direktori dan file password VNC untuk pengguna baru
RUN mkdir -p /home/${USERNAME}/.vnc && \
    echo "${VNC_PASSWORD}" | vncpasswd -f > /home/${USERNAME}/.vnc/passwd && \
    chmod 600 /home/${USERNAME}/.vnc/passwd && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.vnc

# 6. Membuat skrip startup VNC (xstartup) untuk memulai XFCE
RUN echo "#!/bin/sh" > /home/${USERNAME}/.vnc/xstartup && \
    echo "unset SESSION_MANAGER" >> /home/${USERNAME}/.vnc/xstartup && \
    echo "unset DBUS_SESSION_BUS_ADDRESS" >> /home/${USERNAME}/.vnc/xstartup && \
    echo "exec dbus-launch startxfce4" >> /home/${USERNAME}/.vnc/xstartup && \
    chmod +x /home/${USERNAME}/.vnc/xstartup && \
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.vnc/xstartup

# 7. Konfigurasi Server SSH
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    mkdir -p /run/sshd

# 8. Skrip startup utama yang dimodifikasi untuk menjalankan ngrok
RUN echo "#!/bin/bash" > /startup.sh && \
    echo "dbus-daemon --system &" >> /startup.sh && \
    echo "sleep 2" >> /startup.sh && \
    echo "sudo -u ${USERNAME} vncserver :1 -geometry 1366x768 -depth 24" >> /startup.sh && \
    echo "/usr/sbin/sshd -D &" >> /startup.sh && \
    # Menjalankan ngrok di background untuk port VNC 5901
    echo "/usr/local/bin/ngrok tcp --region \$REGION --authtoken \$NGROK_TOKEN 5901 &" >> /startup.sh && \
    # Beri waktu agar ngrok terhubung
    echo "sleep 8" >> /startup.sh && \
    # Mengambil dan menampilkan URL publik ngrok
    echo "echo '--- Ngrok VNC Access Info ---'" >> /startup.sh && \
    echo "curl -s http://localhost:4040/api/tunnels | python3 -c \"import sys, json; data=json.load(sys.stdin); tunnel=data['tunnels'][0]['public_url'].replace('tcp://', ''); print('Address: ' + tunnel); print('Password: ' + '\$VNC_PASSWORD')\" || echo 'Failed to get ngrok tunnel info. Check logs or ngrok dashboard.'" >> /startup.sh && \
    # Menjaga container tetap berjalan
    echo "tail -f /dev/null" >> /startup.sh && \
    chmod +x /startup.sh

# Expose port (tetap berguna untuk debugging atau koneksi SSH)
EXPOSE 5901 22

# Perintah default saat container dijalankan
CMD ["/bin/bash", "/startup.sh"]
