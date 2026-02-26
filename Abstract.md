# Nacos Kubernetes 项目技术文档

## 项目概述

**Nacos Kubernetes** 是一个全面的云原生解决方案，用于在 Kubernetes 平台上部署 Nacos 服务发现和配置管理。该项目实现了基于 Operator 的架构，并提供 Helm Chart 作为替代方案，提供企业级功能，包括自动扩缩容、多存储支持、健康监控和自动恢复能力。

## 最终架构

### 核心组件

#### 1. Operator 框架 (`operator/`)
- **主控制器**: `NacosReconciler` - 中央协调引擎
- **CRD 定义**: `Nacos` - 自定义资源定义结构
- **服务层**: 多接口设计与专用客户端
- **部署模式**: Standalone 和集群部署支持

#### 2. Helm Charts (`helm/`)
- **Chart 模板**: 基于 StatefulSet 的部署，支持可配置参数
- **存储管理**: 多种存储后端支持（嵌入式、MySQL、NFS、Ceph）
- **服务配置**: Headless 和客户端服务配置
- **Ingress 集成**: 通过 Kubernetes Ingress 进行外部访问

#### 3. 自动扩缩容插件 (`plugin/`)
- **Peer 发现**: 动态集群成员发现
- **服务注册表**: 自动端点更新
- **DNS 配置**: 动态 `/etc/hosts` 修改
- **基于 Hook 的架构**: 事件驱动的插件执行

#### 4. 多存储支持 (`deploy/`)
- **NFS 集成**: 用于持久化存储的网络文件系统
- **Ceph 支持**: 分布式存储后端
- **MySQL 后端**: 用于数据持久化的外部数据库
- **本地存储**: 开发和测试部署

### 数据流架构

```
CRD 请求 → NacosReconciler → 资源验证 → 资源创建 → 状态更新
     ↓              ↓                  ↓                ↓              ↓
  NacosSpec → 阶段管理 → Kubernetes 资源 → 健康检查 → 事件日志
```

## 重要类和函数分析

### 1. 主控制器 (`operator/controllers/nacos_controller.go`)

**类: `NacosReconciler`**
- **目的**: 实现 Kubernetes 控制器模式的核心协调引擎
- **关键函数**:
  - `Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error)` - 协调循环的入口点
  - `ReconcileWork(instance *nacosgroupv1alpha1.Nacos) bool` - 主要编排工作流程，包含 panic 恢复

**关键工作流程**:
```go
func (r *NacosReconciler) ReconcileWork(instance *nacosgroupv1alpha1.Nacos) bool {
    // 顺序协调管道
    r.PreCheck(instance)           // 阶段验证和初始化
    r.MakeEnsure(instance)        // 资源创建和管理
    r.CheckAndMakeHeal(instance)  // 健康验证和恢复
    r.UpdateStatus(instance)       // 最终状态更新
    return true
}
```

**错误处理**: 使用 `globalExceptHandle` 方法进行全局异常处理，panic 触发 5 秒延迟重新排队

### 2. CRD Structure (`operator/api/v1alpha1/nacos_types.go`)

**类: `Nacos`**
- **目的**: 表示期望和实际状态的主要 CRD 结构
- **关键字段**:
  - `Spec` - 期望状态，包括镜像、副本数、资源
  - `Status` - 实际状态，包含阶段、条件、事件

**类: `NacosSpec`**
```go
type NacosSpec struct {
    Image      string            `json:"image"`           // 容器镜像
    Replicas   *int32            `json:"replicas"`        // 集群副本数
    Resources  v1.ResourceRequirements `json:"resources"`   // CPU/内存限制
    Database   Database          `json:"database"`        // 数据库配置
    Type       string            `json:"type"`           // "standalone" 或 "cluster"
    Config     string            `json:"config"`         // 自定义配置
    Volume     Storage           `json:"volume"`         // 存储配置
    // ... 其他字段
}
```

**类: `NacosStatus`**
```go
type NacosStatus struct {
    Phase      Phase             `json:"phase"`          // 部署阶段
    Conditions []Condition       `json:"conditions"`     // 健康条件
    Events     []Event           `json:"events"`         // 事件历史
    Version    string            `json:"version"`        // Nacos 版本
}
```

**阶段常量**:
- `PhaseRunning` - 正常运行
- `PhaseCreating` - 部署进行中  
- `PhaseFailed` - 部署失败
- `PhaseScale` - 扩缩容操作

### 3. 核心 Operator 逻辑 (`operator/pkg/service/operator/operaror.go`)

**接口: `IOperatorClient`**
- **目的**: 组合所有 Operator 功能的主接口
- **组成**: 聚合 IKindClient、ICheckClient、IHealClient、IStatusClient

**类: `OperatorClient`**
```go
type OperatorClient struct {
    kind    IKindClient    // 资源创建和管理
    check   ICheckClient   // 健康验证
    heal    IHealClient    // 资源恢复
    status  IStatusClient  // 状态管理
}
```

**关键函数**:
- `NewOperatorClient()` - 创建所有服务客户端的工厂方法
- `MakeEnsure(nacos *Nacos)` - 基于部署类型的资源编排
- `PreCheck(nacos *Nacos)` - 状态验证和阶段转换
- `UpdateStatus(nacos *Nacos)` - 最终状态更新

**部署类型处理**:
- **Standalone 模式**: ConfigMap + StatefulSet + Service
- **Cluster 模式**: ConfigMap + StatefulSet + Headless Service + Client Service

### 4. Kubernetes 服务层 (`operator/pkg/service/k8s/`)

**接口: `Services`**
- **目的**: 所有 Kubernetes 操作的统一接口
- **方法**: ConfigMap、Service、StatefulSet、Job 管理

**类: `services`**
- **目的**: 实现所有服务接口的聚合容器
- **关键方法**:
  - `CreateOrUpdateStatefulSet()` - 智能 StatefulSet 管理
  - `CreateIfNotExistsService/ConfigMap()` - 幂等资源创建

**关键特性**:
- 需要重新创建 StatefulSet 的卷模板更改检测
- 客户端服务的 IPv4/IPv6 双栈支持
- 资源的后台传播删除

### 5. 专用 Operator 客户端

#### Kind Client (`operator/pkg/service/operator/kind.go`)
- **目的**: 资源生成和管理
- **关键函数**:
  - `CreateConfigMap()` - 使用 Nacos 配置创建 ConfigMap
  - `CreateStatefulSet()` - StatefulSet 生命周期管理
  - `CreateJob()` - 数据库初始化作业

#### Check Client (`operator/pkg/service/operator/check.go`)
- **目的**: 健康验证和状态监控
- **关键函数**:
  - `CheckReplica()` - 验证 StatefulSet 副本是否匹配 CR 规范
  - `CheckNacosCluster()` - 验证集群健康和一致性
  - `MinPodHealthCheck()` - 基于法定人数的 Pod 健康验证

#### Status Client (`operator/pkg/service/operator/status.go`)
- **目的**: 状态管理和事件日志
- **关键函数**:
  - `UpdateStatus()` - 使用阶段转换更新资源状态
  - `AddEvent()` - 向历史记录添加事件（最多10个事件）
  - `SetPhase()` - 更新部署阶段

#### Heal Client (`operator/pkg/service/operator/heal.go`)
- **目的**: 自动恢复和资源恢复
- **状态**: 当前为占位符（TODO 实现）

### 6. 自动扩缩容插件 (`plugin/peer/plugin.sh`)

**核心功能**:
- **Peer 发现**: 通过服务 DNS 进行动态集群成员发现
- **主机文件管理**: 为服务解析修改 `/etc/hosts`
- **域处理**: 规范化 `cluster.local` 域条目
- **Peer-Finder 集成**: 使用发现参数执行 peer-finder

**关键操作**:
```bash
# 主插件工作流程
clean_hosts_entries()               # 清理现有条目
peer_finder --on-start on-start.sh --on-change on-change.sh
```

## 功能流程

### 1. 部署流程
```
CRD 创建 → NacosReconciler.Reconcile() → 资源验证 → 资源创建
     ↓                ↓                  ↓                ↓
阶段设置 → KindClient.MakeEnsure() → Kubernetes 资源 → 状态更新
```

### 2. 集群管理流程
```
NacosSpec.Replicas → StatefulSet 更新 → Pod 创建 → Peer 发现
     ↓                  ↓                ↓              ↓
Phase.Scale → 服务发现 → 插件激活 → DNS 解析
```

### 3. 数据持久化流程
```
数据库配置 → 存储类 → PVC 创建 → 容器挂载
     ↓                   ↓              ↓                ↓
MySQL 模式 → 作业初始化 → 数据持久化 → 卷声明
```

### 4. 健康监控流程
```
资源创建 → CheckClient 验证 → Status Client 更新 → 事件日志
     ↓                ↓                  ↓                ↓
Pod 健康检查 → 集群一致性 → 阶段管理 → 错误处理
```

## 配置属性

### 环境变量
- `MODE` - 部署模式（standalone/cluster）
- `NACOS_SERVERS` - 集群服务器列表
- `PREFER_HOST_MODE` - 主机名偏好设置
- `SPRING_DATASOURCE_PLATFORM` - 数据库类型（mysql/embedded）

### 存储配置
- `NFS_SERVER` - NFS 服务器地址
- `NFS_PATH` - NFS 共享目录
- `MYSQL_HOST` - 数据库主机
- `MYSQL_DATABASE` - 数据库名称
- `MYSQL_USER` - 数据库用户名
- `MYSQL_PASSWORD` - 数据库密码

## 关键特性

### 1. 基于 Operator 的管理
- 通过 CRD 进行声明式资源管理
- 自动协调循环
- 多层客户端架构
- 全面的错误处理和恢复

### 2. 多模式部署
- **Standalone 模式**: 带嵌入式数据库的单实例
- **Cluster 模式**: 带外部数据库的多实例
- **自动扩缩容**: 动态副本管理
- **自动恢复**: 自动故障恢复

### 3. 存储灵活性
- **嵌入式数据库**: 开发和测试
- **外部 MySQL**: 生产持久化
- **NFS 存储**: 网络文件系统后端
- **Ceph 存储**: 分布式存储支持

### 4. 服务集成
- **Headless 服务**: 内部集群通信
- **客户端服务**: 外部应用程序访问
- **Ingress 集成**: HTTP/HTTPS 外部访问
- **双栈支持**: IPv4/IPv6 网络

### 5. 监控和可观察性
- **事件历史**: 部署事件跟踪
- **阶段管理**: 部署状态跟踪
- **健康检查**: Pod 和集群验证
- **状态更新**: 实时状态同步

## 生产就绪性

### 安全特性
- RBAC（基于角色的访问控制）
- 基于令牌的身份验证
- 数据库凭据的密钥管理
- 网络策略支持

### 高可用性
- 多副本集群部署
- 集群模式中的领导者选举
- 自动故障转移和恢复
- 基于法定人数的一致性

### 可扩展性
- 水平 Pod 扩缩容
- StatefulSet 稳定性
- 资源限制管理
- 负载分发

---

这个 Nacos Kubernetes 项目提供了一个强大、生产就绪的解决方案，用于部署具有企业级功能、全面监控和多云兼容性的 Nacos 服务发现和配置管理。