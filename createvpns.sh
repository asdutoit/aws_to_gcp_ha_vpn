#!/bin/bash

GCP_VPC_NAME=gc-vpc 
GCP_SUBNET_MODE=custom # custom or automatic
GCP_BGP_ROUTING_MODE=global # regional or global
GCP_SUBNET_NAME=subnet-east4 
GCP_REGION=us-east4
GCP_SUBNET_CIDR=10.1.1.0/24

GCP_VPN_GATEWAY_NAME=gcp-aws-homerunner-vpn-gw 
GCP_CLOUD_ROUTER=gcp-homerunner-cloudrouter
GCP_ASN_NUMBER=65534 # Any number between 64512-65534 or 4200000000-4294967294
GCP_HA_VPN_GATEWAY_PUBLIC_IP_1=""
GCP_HA_VPN_GATEWAY_PUBLIC_IP_2=""

AWS_VPC_ID=vpc-059aef060320397c4
AWS_ASN_NUMBER=64512
AWS_T1_INSIDE_IP=169.254.12.0/30
AWS_T2_INSIDE_IP=169.254.13.0/30
AWS_T3_INSIDE_IP=169.254.14.0/30
AWS_T4_INSIDE_IP=169.254.15.0/30
SHARED_SECRET=supersecretpw
AWS_CGW_1_ID=""
AWS_CGW_2_ID=""
AWS_VPG_ID=""
#

# NOTE: The following IPs should be extracted from the AWS VPN configuration files after completin Step 3
VPG_OUTSIDE_IP_1=13.245.54.33
VPG_OUTSIDE_IP_2=13.245.130.82
VPG_OUTSIDE_IP_3=13.244.196.204
VPG_OUTSIDE_IP_4=13.246.149.147
CGW_INSIDE_IP_1=169.254.12.2
CGW_INSIDE_IP_2=169.254.13.2
CGW_INSIDE_IP_3=169.254.14.2
CGW_INSIDE_IP_4=169.254.15.2
VPG_INSIDE_IP_1=169.254.12.1
VPG_INSIDE_IP_2=169.254.13.1
VPG_INSIDE_IP_3=169.254.14.1
VPG_INSIDE_IP_4=169.254.15.1
GCP_EXTERNAL_VPN_GATEWAY_NAME=aws-peer-gw

# ================================ #
# 1.  Create a custom VPC network with a single subnet:
# ================================ #

# Create a single VPC
create_gcp_vpc(){
  gcloud compute networks create ${GCP_VPC_NAME} \
 --subnet-mode ${GCP_SUBNET_MODE} \
 --bgp-routing-mode ${GCP_BGP_ROUTING_MODE}
}

# Create a single Subnet
create_gcp_subnet(){
  gcloud compute networks subnets create ${GCP_SUBNET_NAME} \
 --network ${GCP_VPC_NAME} \
 --region ${GCP_REGION} \
 --range ${GCP_SUBNET_CIDR}
}

# ================================ #



# ================================ #
# 2.  Create the HA VPN gateway and Cloud Router:
# ================================ #

#

# Create VPN Gateway
create_gcp_ha_vpn_gateway(){
  gcloud compute vpn-gateways create ${GCP_VPN_GATEWAY_NAME} \
 --network ${GCP_VPC_NAME} \
 --region ${GCP_REGION}
 
 resp=$(gcloud compute vpn-gateways describe ${GCP_VPN_GATEWAY_NAME} --format json | jq ".vpnInterfaces");

 GCP_HA_VPN_GATEWAY_PUBLIC_IP_1_PRE=$(echo $resp | jq '.[0].ipAddress')
 GCP_HA_VPN_GATEWAY_PUBLIC_IP_2_PRE=$(echo $resp | jq '.[1].ipAddress')
 GCP_HA_VPN_GATEWAY_PUBLIC_IP_1=$(echo "${GCP_HA_VPN_GATEWAY_PUBLIC_IP_1_PRE//\"/}")
 GCP_HA_VPN_GATEWAY_PUBLIC_IP_2=$(echo "${GCP_HA_VPN_GATEWAY_PUBLIC_IP_2_PRE//\"/}")
 echo $GCP_HA_VPN_GATEWAY_PUBLIC_IP_1 
 echo $GCP_HA_VPN_GATEWAY_PUBLIC_IP_2
}

# Create Cloud Router
create_gcp_cloud_router(){
  gcloud compute routers create ${GCP_CLOUD_ROUTER} \
--region ${GCP_REGION} \
--network ${GCP_VPC_NAME} \
--asn ${GCP_ASN_NUMBER} \
--advertisement-mode custom \
--set-advertisement-groups all_subnets
}
# ================================ #


# ================================ #
# 3.  Create Gateways and VPN connections on AWS:
# ================================ #

# Create two customer gateways:
create_aws_customer_gateways(){
  resp1=$(aws ec2 create-customer-gateway --type ipsec.1 --public-ip ${GCP_HA_VPN_GATEWAY_PUBLIC_IP_1} --bgp-asn ${GCP_ASN_NUMBER})
  resp2=$(aws ec2 create-customer-gateway --type ipsec.1 --public-ip ${GCP_HA_VPN_GATEWAY_PUBLIC_IP_2} --bgp-asn ${GCP_ASN_NUMBER})
  AWS_CGW_1_ID_PRE=$(echo $resp1 | jq '.CustomerGateway.CustomerGatewayId')
  AWS_CGW_2_ID_PRE=$(echo $resp2 | jq '.CustomerGateway.CustomerGatewayId')
  AWS_CGW_1_ID=$(echo "${AWS_CGW_1_ID_PRE//\"/}" )
  AWS_CGW_2_ID=$(echo "${AWS_CGW_2_ID_PRE//\"/}" )
  echo $AWS_CGW_1_ID
  echo $AWS_CGW_2_ID
}

# Create Virtual Private Gateway:
create_aws_vpg(){
  resp=$(aws ec2 create-vpn-gateway --type ipsec.1 --amazon-side-asn ${AWS_ASN_NUMBER} | jq ".VpnGateway.VpnGatewayId")
  AWS_VPG_ID=$(echo "${resp//\"/}")
  echo $AWS_VPG_ID
}

# Attach Virtual Private Gateway to VPC:
attach_aws_vpg_to_vpc(){
  aws ec2 attach-vpn-gateway --vpn-gateway-id ${AWS_VPG_ID} --vpc-id ${AWS_VPC_ID}
}

# Create 2x VPN connections with dynamic routing
create_aws_vpn_connections(){
  aws ec2 create-vpn-connection \
--type ipsec.1 \
--customer-gateway-id ${AWS_CGW_1_ID} \
--vpn-gateway-id ${AWS_VPG_ID} \
--options TunnelOptions='[{TunnelInsideCidr='${AWS_T1_INSIDE_IP}',PreSharedKey='${SHARED_SECRET}'},{TunnelInsideCidr='${AWS_T2_INSIDE_IP}',PreSharedKey='${SHARED_SECRET}'}]'

aws ec2 create-vpn-connection \
--type ipsec.1 \
--customer-gateway-id ${AWS_CGW_2_ID} \
--vpn-gateway-id ${AWS_VPG_ID} \
--options TunnelOptions='[{TunnelInsideCidr='${AWS_T3_INSIDE_IP}',PreSharedKey='${SHARED_SECRET}'},{TunnelInsideCidr='${AWS_T4_INSIDE_IP}',PreSharedKey='${SHARED_SECRET}'}]'
}

# Remember to download the configuration file from AWS Console
# ================================ #



# ================================ #
# 4.  Create VPN Tunnels and Cloud Router Interfaces on GCP
# ================================ #


# Create External VPN Gateway with 4x interfaces for the AWS outside IP addresses
create_gcp_external_vpn_gateway(){
  gcloud compute external-vpn-gateways create ${GCP_EXTERNAL_VPN_GATEWAY_NAME} --interfaces \
 0=${VPG_OUTSIDE_IP_1},1=${VPG_OUTSIDE_IP_2},2=${VPG_OUTSIDE_IP_3},3=${VPG_OUTSIDE_IP_4}
}

# Create 4x Tunnels

create_gcp_tunnels(){
  gcloud compute vpn-tunnels create tunnel-1 \
 --peer-external-gateway ${GCP_EXTERNAL_VPN_GATEWAY_NAME} \
 --peer-external-gateway-interface 0 \
 --region ${GCP_REGION} \
 --ike-version 2 \
 --shared-secret ${SHARED_SECRET} \
 --router ${GCP_CLOUD_ROUTER} \
 --vpn-gateway ${GCP_VPN_GATEWAY_NAME} \
 --interface 0

 gcloud compute vpn-tunnels create tunnel-2 \
 --peer-external-gateway ${GCP_EXTERNAL_VPN_GATEWAY_NAME} \
 --peer-external-gateway-interface 1 \
 --region ${GCP_REGION} \
 --ike-version 2 \
 --shared-secret ${SHARED_SECRET} \
 --router ${GCP_CLOUD_ROUTER} \
 --vpn-gateway ${GCP_VPN_GATEWAY_NAME} \
 --interface 0

 gcloud compute vpn-tunnels create tunnel-3 \
 --peer-external-gateway ${GCP_EXTERNAL_VPN_GATEWAY_NAME} \
 --peer-external-gateway-interface 2 \
 --region ${GCP_REGION} \
 --ike-version 2 \
 --shared-secret ${SHARED_SECRET} \
 --router ${GCP_CLOUD_ROUTER} \
 --vpn-gateway ${GCP_VPN_GATEWAY_NAME} \
 --interface 1

 gcloud compute vpn-tunnels create tunnel-4 \
 --peer-external-gateway ${GCP_EXTERNAL_VPN_GATEWAY_NAME} \
 --peer-external-gateway-interface 3 \
 --region ${GCP_REGION} \
 --ike-version 2 \
 --shared-secret ${SHARED_SECRET} \
 --router ${GCP_CLOUD_ROUTER} \
 --vpn-gateway ${GCP_VPN_GATEWAY_NAME} \
 --interface 1

}

# Create four Cloud Router interfaces

create_gcp_cloud_router_interfaces(){
  gcloud compute routers add-interface ${GCP_CLOUD_ROUTER} \
 --interface-name int-1 \
 --vpn-tunnel tunnel-1 \
 --ip-address ${CGW_INSIDE_IP_1} \
 --mask-length 30 \
 --region ${GCP_REGION}

 gcloud compute routers add-interface ${GCP_CLOUD_ROUTER} \
 --interface-name int-2 \
 --vpn-tunnel tunnel-2 \
 --ip-address ${CGW_INSIDE_IP_2} \
 --mask-length 30 \
 --region ${GCP_REGION}

 gcloud compute routers add-interface ${GCP_CLOUD_ROUTER} \
 --interface-name int-3 \
 --vpn-tunnel tunnel-3 \
 --ip-address ${CGW_INSIDE_IP_3} \
 --mask-length 30 \
 --region ${GCP_REGION}

 gcloud compute routers add-interface ${GCP_CLOUD_ROUTER} \
 --interface-name int-4 \
 --vpn-tunnel tunnel-4 \
 --ip-address ${CGW_INSIDE_IP_4} \
 --mask-length 30 \
 --region ${GCP_REGION}
}


# Add BGP Peers

add_gcp_bgp_peers(){
  gcloud compute routers add-bgp-peer ${GCP_CLOUD_ROUTER} \
 --peer-name tunnel-1 \
 --peer-asn ${AWS_ASN_NUMBER} \
 --interface int-1 \
 --peer-ip-address ${VPG_INSIDE_IP_1} \
 --region ${GCP_REGION}

 gcloud compute routers add-bgp-peer ${GCP_CLOUD_ROUTER} \
 --peer-name tunnel-2 \
 --peer-asn ${AWS_ASN_NUMBER} \
 --interface int-2 \
 --peer-ip-address ${VPG_INSIDE_IP_2} \
 --region ${GCP_REGION}

  gcloud compute routers add-bgp-peer ${GCP_CLOUD_ROUTER} \
 --peer-name tunnel-3 \
 --peer-asn ${AWS_ASN_NUMBER} \
 --interface int-3 \
 --peer-ip-address ${VPG_INSIDE_IP_3} \
 --region ${GCP_REGION}

  gcloud compute routers add-bgp-peer ${GCP_CLOUD_ROUTER} \
 --peer-name tunnel-4 \
 --peer-asn ${AWS_ASN_NUMBER} \
 --interface int-4 \
 --peer-ip-address ${VPG_INSIDE_IP_4} \
 --region ${GCP_REGION}
}


# ================================ #
# 5.  Verify the configuration
# ================================ #

verify_gcp_vpn_connection(){
  gcloud compute routers get-status ${GCP_CLOUD_ROUTER} \
 --region ${GCP_REGION} \
 --format='flattened(result.bgpPeerStatus[].name, result.bgpPeerStatus[].ipAddress, result.bgpPeerStatus[].peerIpAddress)'
}