#!/usr/bin/env bash

echo "mysql mysql ending"
kubectl delete -f ./deploy/mysql/mysql-local.yaml


echo "nacos quick ending"
kubectl delete -f ./deploy/nacos/nacos-quick-start.yaml
