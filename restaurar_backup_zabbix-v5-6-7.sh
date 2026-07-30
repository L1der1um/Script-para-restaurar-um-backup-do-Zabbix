#!/bin/bash

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_splash() {
    clear
    echo -e "\e[31m"
    echo "███████╗ █████╗ ██████╗ ██████╗ ██╗██╗  ██╗"
    echo "╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██║╚██╗██╔╝"
    echo "  ███╔╝ ███████║██████╔╝██████╔╝██║ ╚███╔╝ "
    echo " ███╔╝  ██╔══██║██╔══██╗██╔══██╗██║ ██╔██╗ "
    echo "███████╗██║  ██║██████╔╝██████╔╝██║██╔╝ ██╗"
    echo "╚══════╝╚═╝  ╚═╝╚═════╝╚═════╝ ╚═╝╚═╝  ╚═╝"
    echo -e "\e[0m"
    echo "========================================================"
    echo "               RESTAURAÇÃO ZABBIX 7 LTS"
    echo "========================================================"
    echo ""
    sleep 2
}

show_splash

BACKUP_DIR="/backup_zabbix"

if [ "$(id -u)" != "0" ]; then
    echo "❌ Este script deve ser executado como root."
    exit 1
fi

selecionar_backup() {
    echo -e "\n📂 Backups disponíveis em $BACKUP_DIR:"
    local backups=($(ls -1t "$BACKUP_DIR" | grep ^bkp_))

    if [ ${#backups[@]} -eq 0 ]; then
        echo "❌ Nenhum backup encontrado em $BACKUP_DIR"
        exit 1
    fi

    for i in "${!backups[@]}"; do
        echo "$((i+1)). ${backups[$i]} ($(du -sh "$BACKUP_DIR/${backups[$i]}" | cut -f1))"
    done

    read -p "👉 Selecione o backup para restaurar (1-${#backups[@]}): " backup_num
    selected_backup="${backups[$((backup_num-1))]}"
    BACKUP_PATH="$BACKUP_DIR/$selected_backup"

    if [ ! -d "$BACKUP_PATH" ]; then
        echo "❌ Backup selecionado inválido"
        exit 1
    fi

    echo -e "\n🔍 Itens no backup selecionado:"
    ls -lh "$BACKUP_PATH"
}

restaurar_zabbix() {
    echo -e "\n🔵 Iniciando Restauração do Zabbix..."

    local zabbix_db_file=$(find "$BACKUP_PATH" -name "zabbix_db_*.sql.gz" | head -1)
    if [ ! -f "$zabbix_db_file" ]; then
        echo "❌ Arquivo do banco de dados Zabbix não encontrado em $BACKUP_PATH"
        exit 1
    fi

    read -p "👉 Usuário do MySQL (ex: zabbix): " mysql_user
    read -s -p "🔒 Senha do MySQL: " mysql_pass
    echo ""

    echo "🛑 Parando serviços do Zabbix para evitar gravações concorrentes..."
    systemctl stop zabbix-server zabbix-agent apache2 2>/dev/null

    echo "🔓 Destrancando segurança de funções do MySQL (Prevenção do Erro 1419)..."
    mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 1;" 2>/dev/null

    echo "🧹 Preparando banco de dados limpo..."
    if ! MYSQL_PWD="$mysql_pass" mysql -u "$mysql_user" -e "DROP DATABASE IF EXISTS zabbix; CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"; then
        echo "❌ Falha ao recriar o banco de dados. Verifique as credenciais."
        mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null
        exit 1
    fi

    echo "🔄 Processando injeção de dados (isto pode demorar)..."
    local log_file=$(mktemp)
    
    zcat "$zabbix_db_file" | sed \
        -e "s/utf8mb4_0900_[a-z_]*/utf8mb4_general_ci/g" \
        -e "s/utf8mb3_/utf8_/g" \
        -e "s/COLLATE utf8mb4_bin/COLLATE utf8mb4_general_ci/g" \
        -e "s/DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin/DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci/g" \
        -e "s/CHARACTER SET utf8mb4/CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci/g" \
        -e "s/ENGINE=InnoDB/ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci/g" \
        | MYSQL_PWD="$mysql_pass" mysql -u "$mysql_user" zabbix 2>"$log_file"
    
    if [ $? -eq 0 ]; then
        echo "✅ Banco de dados restaurado com sucesso!"
        rm -f "$log_file"
    else
        echo "❌ Falha na restauração do banco. Erros encontrados:"
        cat "$log_file"
        mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null
        exit 1
    fi

    echo "🔒 Trancando segurança de funções do MySQL novamente..."
    mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null

    local zabbix_files=$(find "$BACKUP_PATH" -name "zabbix_dirs_*.tar.gz" | head -1)
    if [ -f "$zabbix_files" ]; then
        echo "🔄 Restaurando arquivos físicos do Zabbix..."
        if ! tar -xzf "$zabbix_files" -C /; then
            echo "❌ Falha ao extrair arquivos de configuração."
            exit 1
        fi
        echo "✅ Arquivos físicos restaurados com sucesso."
    else
        echo "⚠️  Arquivos de configuração (tar.gz) não encontrados. Apenas o banco foi restaurado."
    fi
    
    echo "🚀 Reiniciando serviços do Zabbix..."
    systemctl start zabbix-server zabbix-agent apache2
}

selecionar_backup
restaurar_zabbix

echo -e "\n✅ Restauração do Zabbix concluída!"
echo "================================="