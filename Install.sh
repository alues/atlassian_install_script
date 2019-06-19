#!/usr/bin/env bash

cur_path=`cd "$(dirname "$0")"; pwd`
cur_sys=`cat /etc/*-release | sed -r "s/^ID=(.*)$/\\1/;tA;d;:A;s/^\"(.*)\"$/\\1/" | tr -d '\n'`
cur_pkg_path=${cur_path}/pkg

# Stop the script when any Error occur
set -e

# Software version env
BITBUCKET_VERSION=6.3.2

INSTALL_ROOT=/opt/atlassian
JAVA_AGENT_OPT=/opt/atlassian/atlassian-agent.jar
RUNTIME_DATA_ROOT=/var/atlassian/application-data

# Domain setting
MAIN_DOMAIN=exmaple.com
SUBDOMAIN_CROWD=sso.${MAIN_DOMAIN}
SUBDOMAIN_CROWD_PORT=80
SUBDOMAIN_JIRA=flow.${MAIN_DOMAIN}
SUBDOMAIN_JIRA_PORT=80
SUBDOMAIN_CONFLUENCE=doc.${MAIN_DOMAIN}
SUBDOMAIN_CONFLUENCE_PORT=80
SUBDOMAIN_BITBUCKET=git.${MAIN_DOMAIN}
SUBDOMAIN_BITBUCKET_PORT=80

# SSO setting
SSO_APPLICATION_NAME=sso
SSO_APPLICATION_PASSWORD="password"
SSO_DOMAIN=${SUBDOMAIN_CROWD}
# SSO_DOMAIN=localhost:8095
SSO_BASE_URL=http://${SSO_DOMAIN}/crowd/
SSO_LOGIN_URL=${SSO_BASE_URL}console/
SSO_SERVER_URL=${SSO_BASE_URL}services/

# ====================================
# functions

_color_red='\E[1;31m'
_color_green='\E[1;32m'
_color_yellow='\E[1;33m'
_color_blue='\E[1;34m'
_color_wipe='\E[0m'

function print_err() {
    # ${1} msg string
    # ${2} special tag
    _tmp_status=${2:-Error  }
    printf "[${_color_red} ${_tmp_status} ${_color_wipe}] ${1}\n"
}

function print_success() {
    # ${1} msg string
    # ${2} special tag
    _tmp_status=${2:-Success}
    printf "[${_color_green} ${_tmp_status} ${_color_wipe}] ${1}\n"
}

function print_warning() {
    # ${1} msg string
    # ${2} special tag
    _tmp_status=${2:-Warning}
    printf "[${_color_yellow} ${_tmp_status} ${_color_wipe}] ${1}\n"
}

function print_info() {
    # ${1} msg string
    # ${2} special tag
    _tmp_status=${2:-Info   }
    printf "[${_color_blue} ${_tmp_status} ${_color_wipe}] ${1}\n"
}

function backup_check() {
    # ${1} file path
    # ${2} force replace
    if [[ ! -f ${1}.bak || ${2} ]]; then
        print_info "backup \`${1}\`"
        cp -rf ${1} ${1}.bak
    fi
}

function parse_run_method() {
    print_info "parsing enrty"
    _tmp_list=(`ls /opt/atlassian`)

    for ((i=1; i<=${#var_list[@]}; i++)); do
        print_info ${i}
    done
}

function init_env() {
    print_info "Initing env"
    _tmp_root=$(dirname ${JAVA_AGENT_OPT})
    if [[ ! -d ${_tmp_root} ]]; then
        print_info "create folder \`${_tmp_root}\`"
        mkdir -p ${_tmp_root}
    fi

    if [[ ! -f ${JAVA_AGENT_OPT} ]]; then
        print_info "create agent \`${JAVA_AGENT_OPT}\`"
        cp ${cur_pkg_path}/$(basename ${JAVA_AGENT_OPT}) ${JAVA_AGENT_OPT}
    fi
    print_success "Inited env"
}

# ====================================
# common

function init_java_agent() {
    # ${1} software root
    _tmp_list=(
        # default
        setenv.sh
        # bitbucket sp
        _start-webapp.sh
    )

    for v in ${_tmp_list[@]}; do
        _tmp_root=${1}/bin/${v}
        if [[ ! -f ${_tmp_root} ]]; then
            continue
        fi

        backup_check ${_tmp_root}

        print_info "\`${_tmp_root}\` patching"
        awk -v JAVA_AGENT_OPT=${JAVA_AGENT_OPT} \
        'BEGIN{ mark=0; mark_ready=0; mark_NR=0 }/^JAVA_OPTS/{ mark++; mark_NR=NR-mark_NR }{if(mark>0 && mark_ready==0){ mark_ready++; printf "%s\nJAVA_OPTS=\"-javaagent:%s ${JAVA_OPTS}\"\n", $0, JAVA_AGENT_OPT }else if(mark>0 && mark_NR==1){ mark=0 }else{ print }}END{if(mark_ready==0){ printf "export JAVA_OPTS=\"-javaagent:%s ${JAVA_OPTS}\"\n", JAVA_AGENT_OPT }}' \
        ${_tmp_root}.bak > ${_tmp_root}
        print_success "\`${_tmp_root}\` patched"
    done
}

function init_tomcat_config() {
    # ${1} config path
    # ${2} proxy domain
    # ${3} proxy port
    _tmp_root=${1}/conf/server.xml
    if [[ ! -f ${_tmp_root} ]]; then
        return
    fi

    backup_check ${_tmp_root}

    print_info "\`${_tmp_root}\` patching"
    awk -v proxyName=${2} -v proxyPort=${3} \
    'BEGIN{ mark_comment=0; mark_connector=0; mark_proxy_connector=0; connector_config="" }/<!--/{ mark_comment++ }/<Connector/{ mark_connector++; mark_proxy_connector=0; connector_config="" }/scheme="http"/{ mark_proxy_connector++ }/proxyName=/{ mark_proxy_connector++; gsub(/proxyName="[^"]*"/, sprintf("proxyName=\"%s\"", proxyName)) }/proxyPort=/{ mark_proxy_connector++; gsub(/proxyPort="[^"]*"/, sprintf("proxyPort=\"%d\"", proxyPort)) }{if(mark_comment==0 && mark_connector==0){ print }else if(mark_connector>0){ connector_config=sprintf("%s\n%s", connector_config, $0) }}/\/>/{if(mark_connector>0 && mark_proxy_connector==3){ print connector_config } if(mark_connector>0){ mark_connector-- }}/-->/{ mark_comment-- }END{}' \
    ${_tmp_root}.bak > ${_tmp_root}
    print_success "\`${_tmp_root}\` patched"
}

# ====================================
# bitbucket

function init_bitbucket_properties() {
    # ${1} config path
    _tmp_root=${1}/bitbucket.properties
    if [[ ! -d ${1} ]]; then
        return
    elif [[ ! -f ${_tmp_root} ]]; then
        touch ${_tmp_root}
    fi

    backup_check ${_tmp_root} true

    print_info "\`${_tmp_root}\` patching"
    awk -v proxy_name=${SUBDOMAIN_BITBUCKET} -v proxy_port=${SUBDOMAIN_BITBUCKET_PORT} \
    'BEGIN{ mark=0; mark_blank=0 }/^$/{mark_blank++; if(mark_blank>0){ mark++ }}/#proxy server setting/{ mark++ }/server.port=/{ mark++ }/server.secure=/{ mark++ }/server.scheme=/{ mark++ }/server.proxy-port=/{ mark++ }/server.proxy-name=/{ mark++ }{if(mark==0){ print }else{ mark-- }}END{printf("\n#proxy server setting\nserver.port=%d\nserver.secure=%s\nserver.scheme=%s\nserver.proxy-port=%d\nserver.proxy-name=%s\nplugin.auth-crowd.sso.enabled=%s\n", 7990, "false", "http", proxy_port, proxy_name, "true")}' \
    ${_tmp_root}.bak > ${_tmp_root}
    print_success "\`${_tmp_root}\` patched"
}

function init_bitbucket() {
    _software_root=${INSTALL_ROOT}/bitbucket
    if [[ ! -d ${_software_root} ]]; then
        print_warning "software not found : \`${_software_root}\`"
        return
    fi

    if [[ ! -d ${_software_root}/${BITBUCKET_VERSION} ]]; then
        # try to find available bitbucket version
        _tmp_list=(`ls ${_software_root}`)
        if [[ ${#_tmp_list[@]} == 1 ]]; then
            _software_root=${_software_root}/${_tmp_list[0]}
            print_warning "default bitbucket not found, auto switch to \`${_software_root}\`"
        else
            print_info "Please bitbucket version to continue: "
            select _key in ${_tmp_list[@]}; do
                _software_root=${_software_root}/${_key}
                break
            done
        fi
    else
        _software_root=${_software_root}/${BITBUCKET_VERSION}
    fi

    print_info "Init bitbucket"
    init_java_agent ${_software_root}
    init_bitbucket_properties ${RUNTIME_DATA_ROOT}/bitbucket/shared
    print_success "Inited bitbucket"
}

# ====================================
# crowd

function init_crowd_tomcat() {
    # ${1} config path
    _tmp_root=${1}/conf/server.xml
    if [[ ! -f ${_tmp_root} ]]; then
        return
    fi

    backup_check ${_tmp_root}

    print_info "\`${_tmp_root}\` patching"
    awk -v proxyName=${2} -v proxyPort=${3} \
    'BEGIN{ mark=0; mark_count=0 }/<Connector/{ mark++; mark_count++; if(mark_count==1){ printf("%s scheme=\"http\" proxyName=\"%s\" proxyPort=\"%d\"\n", $0, proxyName, proxyPort) }else{ mark-- } }{if(mark==0){ print }else{ mark-- }}' \
    ${_tmp_root}.bak > ${_tmp_root}
    print_success "\`${_tmp_root}\` patched"
}

function init_crowd_properties() {
    # ${1} config path
    _tmp_root=${1}/crowd-webapp/WEB-INF/classes/crowd-init.properties
    _tmp_data_root=/var/atlassian/application-data/crowd
    if [[ ! -f ${_tmp_root} ]]; then
        return
    fi

    backup_check ${_tmp_root}

    print_info "\`${_tmp_root}\` patching"
    awk -v CROWD_HOME=${RUNTIME_DATA_ROOT}/crowd \
    'BEGIN{ mark=0 }/crowd.home=/{ mark++ }{if(mark==0){ print }else if(mark!=2){ print }else{ printf("crowd.home=%s\n", CROWD_HOME) }}' \
    ${_tmp_root}.bak > ${_tmp_root}
    print_success "\`${_tmp_root}\` patched"
}

function init_crowd_sso() {
    # ${1} crowd path
    # seraph-config.xml
    # /opt/atlassian/jira/atlassian-jira/WEB-INF/classes
    _tmp_root=${1}/client/conf/crowd.properties
    
    if [[ ! -f ${_tmp_root} ]]; then
        return
    fi

    # patch 
    sed -ri "s/^(application.name\s+).*$/\\1${SSO_APPLICATION_NAME}/" ${_tmp_root}
    sed -ri "s/^(application.password\s+).*$/\\1${SSO_APPLICATION_PASSWORD}/" ${_tmp_root}
    sed -ri "s/^(application.login.url\s+).*$/\\1${SSO_LOGIN_URL//\//\\/}/" ${_tmp_root}

    sed -ri "s/^(crowd.base.url\s+).*$/\\1${SSO_BASE_URL//\//\\/}/" ${_tmp_root}
    sed -ri "s/^(crowd.server.url\s+).*$/\\1${SSO_SERVER_URL//\//\\/}/" ${_tmp_root}

    _tmp_list=(
        jira/atlassian-jira
        confluence/confluence
    )

    for v in ${_tmp_list[@]}; do
        _tmp_software_root=${INSTALL_ROOT}/${v}/WEB-INF/classes/$(basename ${_tmp_root})
        if [[ ! -d $(dirname ${_tmp_software_root}) ]]; then
            continue
        fi

        print_info "\`${_tmp_software_root}\` sso patching"
        cp -rf ${_tmp_root} ${_tmp_software_root}
        print_success "\`${_tmp_software_root}\` sso patched"
    done

    for v in ${_tmp_list[@]}; do
        _tmp_software_root=${INSTALL_ROOT}/${v}/WEB-INF/classes/seraph-config.xml
        if [[ ! -f ${_tmp_software_root} ]]; then
            continue
        fi

        backup_check ${_tmp_software_root}
        print_info "\`${_tmp_software_root}\` seraph-config patching"
        awk \
        'BEGIN{ mark=0; mark_target=0; mark_NR=0; tmp_str="" }/<!--/{ mark_comment++ }/<authenticator/{ mark_target++ }/SSO/{if(mark_target>0){ mark_target++; tmp_str=$0; gsub(/<!--\s*/, "", tmp_str); gsub(/\s*-->/, "", tmp_str) }}{if(mark_comment==0 && mark_target==0){ print }else if(mark_target==2){ mark_target=0; print tmp_str }}/-->/{if(mark_comment>0){ mark_comment--; mark_target=0 }}' \
        ${_tmp_software_root}.bak > ${_tmp_software_root}
        print_info "\`${_tmp_software_root}\` seraph-config patching"
    done
}

function init_crowd() {
    _software_root=`printf ${INSTALL_ROOT}/atlassian-crowd*`
    if [[ ! -d ${_software_root} ]]; then
        print_warning "software not found : \`${_software_root}\`"
        return
    fi

    print_info "Init crowd"
    init_java_agent ${_software_root}/apache-tomcat
    init_crowd_tomcat ${_software_root}/apache-tomcat ${SUBDOMAIN_CROWD} ${SUBDOMAIN_CROWD_PORT}
    init_crowd_properties ${_software_root}
    init_crowd_sso ${_software_root}
    print_success "Inited crowd"
}

# ====================================
# confluence

function init_confluence() {
    _software_root=${INSTALL_ROOT}/confluence
    if [[ ! -d ${_software_root} ]]; then
        print_warning "software not found : \`${_software_root}\`"
        return
    fi

    print_info "Init confluence"
    init_java_agent ${_software_root}
    init_tomcat_config ${_software_root} ${SUBDOMAIN_CONFLUENCE} ${SUBDOMAIN_CONFLUENCE_PORT}
    print_success "Inited confluence"
}

# ====================================
# jira

function init_jira() {
    _software_root=${INSTALL_ROOT}/jira
    if [[ ! -d ${_software_root} ]]; then
        print_warning "software not found : \`${_software_root}\`"
        return
    fi

    print_info "Init jira"
    init_java_agent ${_software_root}
    init_tomcat_config ${_software_root} ${SUBDOMAIN_JIRA} ${SUBDOMAIN_JIRA_PORT}
    print_success "Inited jira"
}

# ====================================
# install

function install() {
    init_env
    init_jira
    init_crowd
    init_bitbucket
    init_confluence
    print_success "Install Ready"
}

install
