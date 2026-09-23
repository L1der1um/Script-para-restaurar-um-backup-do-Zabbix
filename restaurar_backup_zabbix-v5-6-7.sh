#!/usr/bin/env bash
# ==============================================================================
# Script de Restauração Automatizada - Zabbix 7.0 | 6.0 | 5.0 (Disaster Recovery)
# ==============================================================================

set -e

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
    echo "            RESTAURAÇÃO ZABBIX"
    echo "========================================================"
    echo ""
    sleep 1
}

show_splash

BACKUP_DIR="/backup_zabbix"

# 1. Validação de privilégios
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}❌ Este script deve ser executado como root.${NC}" >&2
    exit 1
fi

# 2. Seleção interativa da pasta de backup (Snapshot do dia)
selecionar_backup() {
    echo -e "\n📂 ${BLUE}Snapshots de backup disponíveis em $BACKUP_DIR:${NC}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ Diretório $BACKUP_DIR não existe.${NC}"
        exit 1
    fi

    mapfile -t backups < <(ls -1td "$BACKUP_DIR"/bkp_* 2>/dev/null | xargs -n1 basename 2>/dev/null)

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}❌ Nenhum diretório de backup (bkp_*) encontrado em $BACKUP_DIR.${NC}"
        exit 1
    fi

    for i in "${!backups[@]}"; do
        local dir_size
        dir_size=$(du -sh "$BACKUP_DIR/${backups[$i]}" | cut -f1)
        echo -e "  ${YELLOW}$((i+1)).${NC} ${backups[$i]} (${dir_size})"
    done

    echo ""
    while true; do
        read -rp "👉 Selecione o diretório de backup [1-${#backups[@]}]: " backup_num
        if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ] && [ "$backup_num" -le "${#backups[@]}" ]; then
            selected_backup="${backups[$((backup_num-1))]}"
            BACKUP_PATH="$BACKUP_DIR/$selected_backup"
            break
        else
            echo -e "${RED}Opção inválida. Digite um número da lista.${NC}"
        fi
    done

    echo -e "\n🔍 ${BLUE}Artefatos identificados em $selected_backup:${NC}"
    ls -lh "$BACKUP_PATH"
}

# 3. Execução da restauração
restaurar_zabbix() {
    echo -e "\n🔵 ${BLUE}Iniciando procedimento de Restauração...${NC}"

    # Identifica todos os dumps relacionais ordenados cronologicamente (mais novo primeiro)
    mapfile -t db_files < <(ls -1t "$BACKUP_PATH"/zabbix_db_*.sql.gz 2>/dev/null)

    local zabbix_db_file=""

    if [ ${#db_files[@]} -eq 0 ]; then
        echo -e "${RED}❌ Erro: Nenhum dump de banco (zabbix_db_*.sql.gz) encontrado em $BACKUP_PATH.${NC}"
        exit 1
    elif [ ${#db_files[@]} -eq 1 ]; then
        zabbix_db_file="${db_files[0]}"
        echo -e "📦 Dump único identificado: ${YELLOW}$(basename "$zabbix_db_file")${NC} ($(du -h "$zabbix_db_file" | cut -f1))"
    else
        echo -e "\n⚠️  ${YELLOW}Múltiplos dumps de banco encontrados. Selecione qual deseja restaurar:${NC}"
        for i in "${!db_files[@]}"; do
            local d_size
            d_size=$(du -h "${db_files[$i]}" | cut -f1)
            echo -e "  ${YELLOW}$((i+1)).${NC} $(basename "${db_files[$i]}") (${d_size})"
        done

        echo ""
        while true; do
            read -rp "👉 Selecione o dump do banco [1-${#db_files[@]}]: " db_num
            if [[ "$db_num" =~ ^[0-9]+$ ]] && [ "$db_num" -ge 1 ] && [ "$db_num" -le "${#db_files[@]}" ]; then
                zabbix_db_file="${db_files[$((db_num-1))]}"
                break
            else
                echo -e "${RED}Opção inválida. Digite um número da lista de dumps.${NC}"
            fi
        done
    fi

    echo -e "\n🎯 Dump selecionado para restauração: ${GREEN}$(basename "$zabbix_db_file")${NC}"

    # Credenciais do Banco
    read -rp "👉 Usuário do MariaDB/MySQL [Padrão: zabbix]: " mysql_user
    mysql_user=${mysql_user:-zabbix}

    read -rsp "🔒 Senha do MariaDB/MySQL [Padrão: zabbix]: " mysql_pass
    echo ""
    mysql_pass=${mysql_pass:-zabbix}

    # Interrompe daemons para integridade referencial
    echo -e "\n🛑 ${YELLOW}[1/5] Parando serviços para garantir integridade referencial...${NC}"
    systemctl stop zabbix-server zabbix-agent apache2 2>/dev/null || true

    # Libera criação de funções sem bloqueio estrito de binlogs
    echo -e "🔓 ${YELLOW}[2/5] Ajustando diretivas de compatibilidade de funções (Erro 1419)...${NC}"
    mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;" 2>/dev/null || true

    # Recriação com a collation mandatória do Zabbix 7.0 LTS
    echo -e "🧹 ${YELLOW}[3/5] Recriando base de dados limpa (utf8mb4_bin)...${NC}"
    if ! MYSQL_PWD="$mysql_pass" mysql -u "$mysql_user" -e "DROP DATABASE IF EXISTS zabbix; CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"; then
        echo -e "${RED}❌ Falha ao recriar banco de dados. Verifique usuário e senha informados.${NC}"
        mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null || true
        exit 1
    fi

    # Injeção em fluxo contínuo
    echo -e "🔄 ${YELLOW}[4/5] Injetando dump relacional selecionado (isto pode levar alguns minutos)...${NC}"
    set -o pipefail
    local err_log
    err_log=$(mktemp)

    if ! zcat "$zabbix_db_file" | MYSQL_PWD="$mysql_pass" mysql -u "$mysql_user" zabbix 2>"$err_log"; then
        echo -e "${RED}❌ Falha na injeção dos dados relacionais:${NC}"
        cat "$err_log"
        rm -f "$err_log"
        mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null || true
        exit 1
    fi
    set +o pipefail
    rm -f "$err_log"
    echo -e "  ${GREEN}✔ Banco de dados importado com sucesso.${NC}"

    # Retorna parâmetro de binlogs
    mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null || true

    # Restauração de configurações físicas
    echo -e "📦 ${YELLOW}[5/5] Restaurando arquivos físicos e configurações...${NC}"
    local zabbix_files
    zabbix_files=$(find "$BACKUP_PATH" -name "zabbix_dirs_*.tar.gz" | head -1)

    if [ -f "$zabbix_files" ]; then
        tar -xzf "$zabbix_files" -C /
        echo -e "  ${GREEN}✔ Configurações e diretórios restaurados na raiz.${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Aviso: Arquivo de diretórios não localizado. Apenas a base foi restaurada.${NC}"
    fi

    # Reinicialização e validação de serviços
    echo -e "\n🚀 ${BLUE}Reiniciando ecossistema de monitoramento...${NC}"
    systemctl restart mariadb 2>/dev/null || true
    systemctl restart zabbix-server zabbix-agent apache2
    
    # Reinicia PHP-FPM se existente
    PHP_SVC=$(systemctl list-units --type=service --state=running | grep -oE "php[0-9.]+-fpm" | head -1 || true)
    [ -n "$PHP_SVC" ] && systemctl restart "$PHP_SVC"

    sleep 2
    if systemctl is-active --quiet zabbix-server; then
        echo -e "\n${GREEN}========================================================"
        echo -e "   ✅ RESTAURAÇÃO CONCLUÍDA: ZABBIX TOTALMENTE OPERACIONAL!"
        echo -e "========================================================${NC}\n"
    else
        echo -e "\n${RED}⚠️  Alerta: O daemon do Zabbix Server não subiu automaticamente. Verifique '/var/log/zabbix/zabbix_server.log'.${NC}\n"
    fi
}

selecionar_backup
restaurar_zabbix
