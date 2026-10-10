# Section 1 — Lab tích hợp: Nền tảng VPC dùng chung cho dev

> Lab này tạo nền tảng mạng đầu tiên cho `dev/lab/`, để các bài và section sau mở rộng cùng một VPC, subnet và Terraform state. Phạm vi cố ý giới hạn ở VPC, hai public subnet, hai private subnet, Internet Gateway và định tuyến public. Không tạo NAT Gateway, VPC endpoint, workload, security group riêng hay network ACL tùy chỉnh trong lab này.

## Mục tiêu lab

Sau khi hoàn thành lab, người học có thể:

- Quy hoạch một VPC IPv4 và bốn subnet không chồng lấn, phân bố public/private qua hai Availability Zone (AZ).
- Triển khai và đọc được route của public subnet đi qua Internet Gateway (IGW), đồng thời xác định vì sao private subnet hiện chưa có đường mặc định ra Internet.
- Tổ chức networking resources trong `dev/lab/` và `modules/networking/` theo một root module/state dùng chung cho các section tiếp theo.
- Dùng AWS Management Console để quan sát account, Region, VPC, AZ, subnet và route table trước khi thay đổi hạ tầng.
- Dùng Terraform `fmt`, `validate` và `plan` để kiểm tra thay đổi, nhận biết CIDR/route/association sai và chỉ apply sau khi đã xác nhận đúng phạm vi.
- Giải thích các thành phần sẽ được giữ lại cho bài NAT Gateway, security groups, VPC endpoints và các lab compute/data về sau.

## 1. Bối cảnh và phạm vi

Các ứng dụng AWS thường cần nhiều lớp mạng. Load balancer public có thể tiếp nhận kết nối từ người dùng, trong khi application và database thường không cần nhận kết nối khởi tạo trực tiếp từ Internet. Trước khi triển khai các workload này, cần tạo một mạng có địa chỉ được quy hoạch, subnet gắn với AZ, route table và ranh giới public/private có thể hiểu và kiểm tra được.

Lab này bắt đầu mạng dùng chung của Section 1 trong Terraform root module `dev/lab/`. Đây không phải một project Terraform tạm riêng cho bài, vì VPC và state sẽ được mở rộng ở các section tiếp theo. Lab cũng không triển khai ứng dụng thật: mục tiêu là tạo và xác minh nền tảng mạng trước khi thêm các dịch vụ tốn phí hoặc có nhiều phụ thuộc.

### Quan hệ với các bài học và lab khác

- **Bài 1 — IAM:** Dùng danh tính AWS phù hợp và quyền tối thiểu để đọc, plan và triển khai tài nguyên. Lab không tạo IAM user, access key hay role quản trị mới.
- **Bài 2 — IPv4/VPC/CIDR:** Áp dụng quy hoạch CIDR cho một VPC và subnet không chồng lấn.
- **Bài 3 — Internet Gateway:** Tạo IGW, public route table, IPv4 default route và subnet association.
- **Bài 4 — NAT Gateway:** Giữ sẵn private subnet và private route table; bài này chưa tạo NAT hay default route cho private subnet.
- **Bài 5 — Security groups và network ACLs:** Dùng default network ACL hiện có để quan sát; chưa tạo SG của workload hoặc NACL tùy chỉnh.
- **Bài 6 — VPC endpoints:** Giữ sẵn private route table để có thể liên kết S3 gateway endpoint sau này.
- **Tài nguyên có sẵn:** Khung file trống trong `dev/lab/` và `dev/lab/modules/networking/`; không giả định VPC hay Terraform state đã tồn tại.
- **Phạm vi tạo mới/thay đổi:** Một VPC IPv4, hai public subnet, hai private subnet, một IGW, một public route table với default route đến IGW, một private route table chỉ có route `local`, và associations tương ứng.
- **Phạm vi ngoài lab:** Compute, ALB, NAT Gateway, VPC endpoints, database, S3 bucket, IAM policies/roles mới, flow logs, custom NACL và mọi thay đổi production.

## 2. Kiến trúc mục tiêu

Lab tạo một VPC dev trong một Region, với một public subnet và một private subnet ở mỗi trong hai AZ. Public subnet được định tuyến đến IGW. Private subnet dùng private route table riêng, chỉ có route `local` do AWS tạo cùng VPC; chưa có route NAT hoặc endpoint.

```text
                         Internet
                            ▲
                            │
                   Internet Gateway
                            ▲
             0.0.0.0/0 → IGW (public route table)
                 ┌──────────┴──────────┐
                 │                     │
         Public subnet AZ-a     Public subnet AZ-b
         10.20.0.0/24           10.20.1.0/24
                 │                     │
         Private subnet AZ-a    Private subnet AZ-b
         10.20.20.0/24          10.20.21.0/24
                 └──────────┬──────────┘
                            │
               Private route table: local only
               (NAT/endpoints sẽ được bổ sung sau)
```

Các CIDR trên là ví dụ, không phải dải bắt buộc. Chỉ sử dụng sau khi xác minh chúng không trùng với mạng hiện có, VPN/on-premises, VPC peering, Transit Gateway hoặc quy hoạch nội bộ.

Luồng và quyết định thiết kế:

1. **VPC cung cấp không gian địa chỉ:** `10.20.0.0/16` là ví dụ về CIDR VPC; bốn subnet được chia thành các khối `/24` riêng, nằm bên trong VPC và không overlap.
2. **Mỗi subnet thuộc một AZ:** Hai public subnet và hai private subnet được trải trên hai AZ để các section sau có thể đặt workload đa AZ. VPC thuộc Region; subnet thuộc một AZ.
3. **Public route table định tuyến ra IGW:** Route `0.0.0.0/0 → IGW` chỉ áp dụng cho public subnet được associate với bảng này. IGW không tự cấp public IPv4 và không tự mở traffic.
4. **Private route table chưa có đường Internet:** Private subnet vẫn có giao tiếp nội bộ VPC qua route `local`; NAT Gateway hoặc VPC endpoint sẽ được thêm sau khi học về chi phí, egress và policy.
5. **Không có workload nên chưa có traffic ứng dụng:** Không tạo EC2/ALB để thử Internet. Điều này tránh phí compute/public IPv4 và tập trung xác minh cấu hình control plane.

### Thành phần và quyết định thiết kế

| Thành phần | Vai trò trong lab | Quyết định cấu hình chính | Lý do và đánh đổi |
|---|---|---|---|
| VPC | Ranh giới mạng IPv4 của lab | Một CIDR được quy hoạch; bật DNS support và DNS hostnames | Là nền tảng cho dịch vụ AWS về sau; CIDR cần đủ chỗ và không overlap. |
| Public subnets | Dự kiến chứa endpoint cần nhận traffic public, như ALB ở section sau | Hai subnet, mỗi AZ một subnet; public route đến IGW; không bật auto-assign public IPv4 | Cho phép đặt public-facing service nhưng không tự làm mọi resource public. |
| Private subnets | Dự kiến chứa application/database workloads | Hai subnet, mỗi AZ một subnet; không cấp public IPv4; chỉ có route `local` | Tạo lớp mạng không có default route trực tiếp ra Internet; NAT/endpoint sẽ được thêm có chủ đích. |
| IGW và public route table | Kết nối và định tuyến IPv4 public subnet | Một IGW, default route `0.0.0.0/0`, associations rõ ràng | Hiển thị đường đi minh bạch; route không thay firewall hay public address. |
| Private route table | Giữ route riêng cho workload private | Một bảng dùng chung trong lab, chỉ route `local` ở bước này | Đơn giản để học; sau này có thể tách route table theo AZ khi thêm NAT/endpoint. |
| Default network ACL | Lớp subnet-level hiện có của VPC | Không thay đổi | Giảm phạm vi lab; NACL tùy chỉnh và ephemeral ports được phân tích ở bài 5. |

## 3. Tách biệt môi trường và cấu hình

Lab này chỉ triển khai dev để dựng nền tảng học tập. Prod được giữ ngoài phạm vi; không chạy `plan` hoặc `apply` ở prod chỉ để sao chép cấu hình dev.

| Hạng mục | Dev | Prod |
|---|---|---|
| Terraform root module | `dev/lab/` | `prod/lab/`, nhưng không triển khai trong lab này |
| State/backend | State riêng cho `dev/lab/`; state phải được khởi tạo và bảo vệ theo cấu hình dự án | State/backend riêng; không dùng chung state/key với dev |
| Tính sẵn sàng | Hai AZ để chuẩn bị cho thực hành compute; chưa có workload failover | Chưa áp dụng; cần thiết kế/duyệt riêng, tính đến AZ mapping, routing, monitoring và yêu cầu availability |
| Egress private subnet | Chưa có NAT hoặc endpoint; private subnet chỉ có route local | Chưa áp dụng |
| Public IPv4 | Không bật auto-assign public IPv4; không tạo EIP | Chưa áp dụng |
| Dọn dẹp | Giữ lại VPC/subnet/state cho Sections 2–5; không destroy cuối lab | Không thay đổi |

Mỗi thư mục `dev/lab/`, `prod/lab/`, `dev/capstone/` và `prod/capstone/` là một root module/state riêng. Lab này chỉ dùng `dev/lab/`; không đổi backend hoặc state để tiện thử nghiệm. Khi triển khai prod trong tương lai, phải xem xét Multi-AZ, subnet sizing, route isolation, logging, kiểm soát thay đổi, quyền backend và quy trình phê duyệt riêng.

## 4. Bảo mật, chi phí và rủi ro

### Bảo mật và quyền truy cập

- **Principal và IAM role:** Dùng danh tính cá nhân/federated hoặc role theo quy trình của account. Tách quyền đọc/plan khỏi quyền apply khi có thể; chỉ cấp các quyền cần cho VPC, subnet, IGW, route table, route, association và đọc trạng thái. Không tạo IAM user/access key mới cho lab.
- **Mạng:** Không tạo workload có public IP. Public subnet chỉ có route; private subnet không có route mặc định ra IGW/NAT. Không mở security group hay cổng ứng dụng trong lab này.
- **Dữ liệu:** Không tạo bucket, database hoặc dữ liệu ứng dụng. VPC CIDR và topology có thể được xem là thông tin nội bộ theo chính sách tổ chức; không đăng công khai nếu không được phép.
- **Secrets:** Không dùng secret trong lab. Không đưa credentials vào HCL, `terraform.tfvars`, backend block, output hoặc logs.
- **Terraform state:** State là dữ liệu cần bảo vệ, có thể chứa metadata/attributes nhạy cảm của tài nguyên ở các section sau. Dùng backend/state riêng của `dev/lab/`, giới hạn quyền truy cập và không commit state file.
- **Xác minh bảo mật:** Xác nhận không có EC2/ALB/EIP được tạo; public subnet auto-assign public IPv4 là `false`; private route table không có default route đến IGW; không có custom ingress rules được thêm.

### Ước tính chi phí

VPC, subnet, IGW, route table và associations thường không có phí theo giờ riêng, nhưng giá AWS và phí liên quan thay đổi theo dịch vụ/Region. Lab không tạo NAT Gateway, interface endpoint, EC2, ALB, EIP hay public IPv4 address; vì vậy tránh được các khoản phí phổ biến từ các tài nguyên này trong bước nền tảng. Trước khi apply, vẫn kiểm tra bảng giá hiện hành và Cost Explorer/Budgets theo account.

| Tài nguyên hoặc hoạt động | Yếu tố chi phí | Cách giới hạn trong lab |
|---|---|---|
| VPC, subnet, IGW, route table | Thường không tính phí theo giờ riêng; xác minh bảng giá AWS hiện hành | Chỉ tạo networking resources trong scope; không thêm service khác |
| Public IPv4/EIP | Public IPv4 có thể tính phí theo chính sách hiện hành; EIP có phí tùy trạng thái/cách dùng | Không bật auto-assign public IPv4; không tạo EIP |
| NAT Gateway | Phí theo giờ và dữ liệu xử lý | Không tạo trong lab; sẽ học riêng ở bài 4 |
| Interface VPC endpoint | Có thể tính phí theo giờ/AZ và dữ liệu | Không tạo trong lab; sẽ đánh giá ở bài 6 |
| Compute, ALB và data transfer | Phụ thuộc loại tài nguyên, thời gian chạy, request và lưu lượng | Không tạo workload để test; chỉ xác minh cấu hình trên Console/plan |
| Terraform backend/logging | Phụ thuộc loại backend, storage, request, encryption và retention | Dùng backend được tổ chức phê duyệt; bảo vệ state và không bật logging tốn phí ngoài scope |

Không xem AWS credit/free tier là đảm bảo không phát sinh chi phí. Nếu AWS plan hiển thị tài nguyên ngoài phạm vi hoặc account policy báo phí không dự kiến, dừng trước khi apply.

### Rủi ro và biện pháp giảm thiểu

| Rủi ro | Hậu quả | Biện pháp giảm thiểu |
|---|---|---|
| CIDR VPC/subnet overlap với mạng hiện có | VPN/peering/TGW routing khó hoặc không hoạt động; cần đổi mạng sau này | Kiểm tra inventory CIDR trước apply; ghi rõ dải được chọn |
| Nhầm account, Region, backend hoặc state | Tạo mạng trong account/state không đúng hoặc ảnh hưởng tài nguyên khác | Xác nhận danh tính/account/Region, thư mục root và backend trước `plan`/`apply` |
| Dùng AZ name không khả dụng trong account/Region | Terraform không tạo được subnet hoặc subnet trải AZ không như ý | Chọn hai AZ khả dụng trên Console/provider; xác nhận cả hai CIDR map đúng AZ |
| Bật auto-assign public IPv4 không cần thiết | Workload mới có thể nhận public address và phát sinh phí/mở rộng bề mặt truy cập | Đặt rõ `map_public_ip_on_launch = false`; cấp public endpoint theo nhu cầu cụ thể |
| Dùng chung private route table khi sau này cần khác biệt per-AZ | Cross-AZ NAT hoặc route blast radius lớn hơn dự tính | Giữ cấu trúc đơn giản cho lab; đánh giá và tách route table khi thêm NAT/HA |
| Destroy root module dùng chung | Mất VPC và networking nền tảng cần cho các section sau | Không destroy sau lab; cleanup chỉ sau xác nhận cuối khóa và review destroy plan đầy đủ |

## 5. Quan sát và chuẩn bị trên AWS Management Console

Trước khi viết Terraform, quan sát account/Region và topology hiện có. Chỉ đọc; không tạo hoặc sửa VPC bằng Console.

1. **Xác nhận danh tính và account.** Mở AWS Management Console, kiểm tra account ID/role đang dùng và xác nhận đây là account dev được phép học. Không tiếp tục nếu account hoặc role không rõ.
2. **Chọn Region và quan sát AZ.** Chọn Region dự định dùng; trong dịch vụ VPC/EC2, xem danh sách Availability Zones có trạng thái khả dụng. Ghi lại hai AZ được chọn. AZ name như `...a` có thể ánh xạ khác nhau giữa account; dùng cùng account cho lab dev và không so sánh tên AZ giữa các account một cách máy móc.
3. **Xem VPC hiện có.** Mở **VPC → Your VPCs** và kiểm tra các VPC/CIDR hiện có. Nếu account đã có mạng học tập hoặc mạng dùng chung, xác nhận rõ lab này được phép dùng dải mới; không thay đổi VPC có sẵn mà chưa biết owner.
4. **Kiểm tra CIDR plan.** So sánh CIDR dự kiến với VPC khác, VPN/on-premises, peering/TGW và dải IP nội bộ đã được cấp. Console có thể không hiển thị toàn bộ mạng ngoài AWS; cần đối chiếu inventory/tài liệu tổ chức.
5. **Quan sát subnet và route table.** Nếu có VPC lab đã tồn tại, lọc subnet/route table theo VPC ID. Ghi nhận subnet CIDR/AZ, route `local`, IGW/default route và association. Nếu chưa có, dùng sơ đồ kiến trúc của lab làm baseline.
6. **Đọc giới hạn và chi phí.** Xem VPC quotas và AWS Pricing/Cost Explorer/Budgets nếu có quyền. Không tạo NAT Gateway, endpoint hoặc EC2 từ Console trong bước quan sát.

## 6. Điều kiện trước khi bắt đầu

- **AWS account/Region:** Có account dev được phép dùng. Chọn một Region và hai AZ đang khả dụng trong account.
- **CIDR đã được duyệt:** Xác minh VPC CIDR và bốn subnet CIDR không overlap với nhau hay mạng khác. Ví dụ dùng trong bài: VPC `10.20.0.0/16`; public `10.20.0.0/24`, `10.20.1.0/24`; private `10.20.20.0/24`, `10.20.21.0/24`.
- **Quyền IAM:** Có quyền đọc account/VPC/AZ và quyền Terraform cần để plan/apply đúng các resource thuộc scope. Không dùng quyền AdministratorAccess làm lựa chọn mặc định.
- **Terraform:** Cài Terraform theo phiên bản dự án; AWS provider version constraint phải được định nghĩa ở `dev/lab/versions.tf` trước `init`.
- **Backend và state:** Xác nhận backend cho `dev/lab/` đã được cấu hình theo quy trình dự án và có key/state riêng. Backend block không nhận nội suy biến Terraform; không ghi credentials backend vào source hoặc tfvars. Nếu backend chưa được thiết lập, dừng trước khi tạo resource và hoàn tất thiết lập state riêng theo quy trình an toàn.
- **Cấu hình cục bộ:** Tạo `terraform.tfvars` từ `terraform.tfvars.example` nếu cần và xác nhận `.gitignore` loại trừ file thật. Chỉ dùng cho Region, CIDR, AZ và giá trị cấu hình không nhạy cảm.
- **Tài nguyên hiện có:** Xác nhận các root/module file đang trống hay đã được sửa; xác định Terraform state có resource nào không. Không ghi đè hoặc tái tạo resource đã có.
- **Chi phí/phê duyệt:** Đọc bảng chi phí; có xác nhận trước khi apply. Không apply vào prod.

## 7. Các bước triển khai

Các đoạn HCL sau mô tả một cách triển khai duy nhất trong module networking dùng chung. Điều chỉnh tên theo code thực tế nếu đã có thay đổi; không khai báo trùng module/resource và không quản lý cùng một AWS resource từ hai Terraform state.

### Giai đoạn A — Kiểm tra trạng thái ban đầu

1. Mở project root và xác nhận `dev/lab/` là Terraform root đang làm việc.
2. Xem `dev/lab/backend.tf`, `versions.tf`, `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf` và thư mục `modules/networking/`.
3. Nếu đây là state mới, kiểm tra backend key là dành riêng cho `dev/lab/`. Nếu state đã có resource, đọc plan/state và tái sử dụng chúng; không khởi tạo lại hoặc đổi key để né drift.
4. Dừng nếu account, Region, state hoặc owner của VPC hiện tại không rõ; CIDR đã được dùng; hoặc plan dự kiến xóa/thay thế resource ngoài phạm vi.

### Giai đoạn B — Cấu hình root module

1. **Khai báo Terraform/provider constraints.** Trong `dev/lab/versions.tf`, ghi phiên bản Terraform/provider theo convention dự án; trong `providers.tf`, cấu hình AWS provider dùng biến Region. Không đặt profile credentials hoặc access keys trong HCL.

   Ví dụ cấu trúc, thay version constraint bằng dải đã được dự án chọn:

   ```hcl
   terraform {
     required_version = ">= 1.5.0"

     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "~> 5.0"
       }
     }
   }
   ```

   Hãy kiểm tra phiên bản Terraform/provider hiện hành trong môi trường dự án; ví dụ chỉ minh họa cú pháp, không yêu cầu nâng cấp tự động.

   ```hcl
   provider "aws" {
     region = var.aws_region
   }
   ```

2. **Định nghĩa root variables.** Trong `dev/lab/variables.tf`, khai báo:

   ```hcl
   variable "aws_region" {
     description = "AWS Region triển khai networking lab."
     type        = string
   }

   variable "availability_zones" {
     description = "Hai AZ khả dụng trong Region của lab."
     type        = list(string)

     validation {
       condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
       error_message = "availability_zones phải gồm đúng hai AZ khác nhau."
     }
   }

   variable "vpc_cidr" {
     description = "CIDR IPv4 đã được quy hoạch cho VPC dev."
     type        = string
   }

   variable "public_subnet_cidrs" {
     description = "Hai CIDR IPv4 không chồng lấn cho public subnets."
     type        = list(string)

     validation {
       condition     = length(var.public_subnet_cidrs) == 2
       error_message = "Cần đúng hai public subnet CIDR."
     }
   }

   variable "private_subnet_cidrs" {
     description = "Hai CIDR IPv4 không chồng lấn cho private subnets."
     type        = list(string)

     validation {
       condition     = length(var.private_subnet_cidrs) == 2
       error_message = "Cần đúng hai private subnet CIDR."
     }
   }
   ```

   Validation trên kiểm tra số lượng AZ/subnet, chưa chứng minh CIDR hợp lệ, nằm trong VPC hoặc không overlap. Các điều kiện địa chỉ phải được xác minh bằng quy hoạch, Console/provider validation và review plan.

3. **Gọi networking module.** Trong `dev/lab/main.tf`, gọi module một lần:

   ```hcl
   module "networking" {
     source = "./modules/networking"

     environment_name     = "dev"
     availability_zones   = var.availability_zones
     vpc_cidr             = var.vpc_cidr
     public_subnet_cidrs  = var.public_subnet_cidrs
     private_subnet_cidrs = var.private_subnet_cidrs
   }
   ```

   Môi trường này nằm trong path `dev/lab/`, nên `environment_name` không cần được lấy từ secret/config. Nếu root đã có module call, cập nhật input đó thay vì thêm block trùng.

4. **Tạo file mẫu tfvars.** Trong `dev/lab/terraform.tfvars.example`, ghi cấu hình ví dụ không nhạy cảm:

   ```hcl
   aws_region          = "ap-northeast-1"
   availability_zones  = ["ap-northeast-1a", "ap-northeast-1c"]
   vpc_cidr            = "10.20.0.0/16"
   public_subnet_cidrs = ["10.20.0.0/24", "10.20.1.0/24"]
   private_subnet_cidrs = ["10.20.20.0/24", "10.20.21.0/24"]
   ```

   Đây chỉ là ví dụ Region/AZ/CIDR. Thay hai AZ bằng AZ thực sự khả dụng trong account/Region đã chọn; thay CIDR nếu quy hoạch mạng yêu cầu. Tạo bản cục bộ `terraform.tfvars` từ mẫu, không commit file thật.

### Giai đoạn C — Tạo networking module

1. **Khai báo module variables.** Trong `dev/lab/modules/networking/variables.tf`, khai báo `environment_name` kiểu `string`, `availability_zones` kiểu `list(string)`, `vpc_cidr` kiểu `string`, `public_subnet_cidrs` và `private_subnet_cidrs` kiểu `list(string)`. Dùng description/validation tương ứng với root inputs. Module cần giữ contract rõ ràng: CIDR list có hai phần tử và AZ list có hai phần tử.

2. **Tạo VPC, AZ mapping và subnet.** Trong `dev/lab/modules/networking/main.tf`, dùng map keyed bởi `"0"`/`"1"` để ổn định Terraform addresses theo vị trí input. HCL minh họa:

   ```hcl
   locals {
     public_subnets = {
       for index, cidr in var.public_subnet_cidrs :
       tostring(index) => {
         cidr = cidr
         az   = var.availability_zones[index]
       }
     }

     private_subnets = {
       for index, cidr in var.private_subnet_cidrs :
       tostring(index) => {
         cidr = cidr
         az   = var.availability_zones[index]
       }
     }
   }

   resource "aws_vpc" "this" {
     cidr_block           = var.vpc_cidr
     enable_dns_support   = true
     enable_dns_hostnames = true

     tags = {
       Name        = "${var.environment_name}-vpc"
       Environment = var.environment_name
     }
   }

   resource "aws_subnet" "public" {
     for_each = local.public_subnets

     vpc_id                  = aws_vpc.this.id
     cidr_block              = each.value.cidr
     availability_zone       = each.value.az
     map_public_ip_on_launch = false

     tags = {
       Name        = "${var.environment_name}-public-${each.key}"
       Environment = var.environment_name
       Network     = "public"
     }
   }

   resource "aws_subnet" "private" {
     for_each = local.private_subnets

     vpc_id                  = aws_vpc.this.id
     cidr_block              = each.value.cidr
     availability_zone       = each.value.az
     map_public_ip_on_launch = false

     tags = {
       Name        = "${var.environment_name}-private-${each.key}"
       Environment = var.environment_name
       Network     = "private"
     }
   }
   ```

   `map_public_ip_on_launch = false` được đặt tường minh cho cả hai loại subnet. Một public-facing ALB không cần bật tự động gán public IPv4 cho mọi EC2 mới trong subnet; về sau tài nguyên public được cấu hình có chủ đích theo service.

3. **Tạo IGW và route table.** Tiếp tục trong `modules/networking/main.tf`:

   ```hcl
   resource "aws_internet_gateway" "this" {
     vpc_id = aws_vpc.this.id

     tags = {
       Name        = "${var.environment_name}-igw"
       Environment = var.environment_name
     }
   }

   resource "aws_route_table" "public" {
     vpc_id = aws_vpc.this.id

     tags = {
       Name        = "${var.environment_name}-public-rt"
       Environment = var.environment_name
     }
   }

   resource "aws_route" "public_ipv4_default" {
     route_table_id         = aws_route_table.public.id
     destination_cidr_block = "0.0.0.0/0"
     gateway_id             = aws_internet_gateway.this.id
   }

   resource "aws_route_table" "private" {
     vpc_id = aws_vpc.this.id

     tags = {
       Name        = "${var.environment_name}-private-rt"
       Environment = var.environment_name
     }
   }
   ```

   AWS tạo route `local` cho CIDR của VPC trong các route table. Không tạo default route cho private table ở lab này. Route table private riêng giúp bước thêm NAT Gateway/VPC endpoint về sau rõ ràng, dù một private table hiện được dùng chung bởi hai AZ.

4. **Associate subnet với route table.** Thêm associations:

   ```hcl
   resource "aws_route_table_association" "public" {
     for_each = aws_subnet.public

     subnet_id      = each.value.id
     route_table_id = aws_route_table.public.id
   }

   resource "aws_route_table_association" "private" {
     for_each = aws_subnet.private

     subnet_id      = each.value.id
     route_table_id = aws_route_table.private.id
   }
   ```

   Mỗi subnet cần có route table association dự kiến. Public association làm default route đến IGW có hiệu lực cho subnet; private association áp dụng bảng chỉ có route local. Không tạo association thứ hai cho cùng subnet.

5. **Tạo outputs.** Trong `dev/lab/modules/networking/outputs.tf`, xuất các ID cần cho module/section sau:

   ```hcl
   output "vpc_id" {
     description = "ID của VPC dùng chung trong dev lab."
     value       = aws_vpc.this.id
   }

   output "public_subnet_ids" {
     description = "Map key sang ID của public subnets."
     value       = { for key, subnet in aws_subnet.public : key => subnet.id }
   }

   output "private_subnet_ids" {
     description = "Map key sang ID của private subnets."
     value       = { for key, subnet in aws_subnet.private : key => subnet.id }
   }

   output "public_route_table_id" {
     description = "ID của public route table."
     value       = aws_route_table.public.id
   }

   output "private_route_table_id" {
     description = "ID của private route table."
     value       = aws_route_table.private.id
   }
   ```

   Trong `dev/lab/outputs.tf`, có thể re-export outputs cần quan sát ở root:

   ```hcl
   output "vpc_id" {
     description = "ID của VPC dùng chung trong dev lab."
     value       = module.networking.vpc_id
   }

   output "public_subnet_ids" {
     description = "Map public subnet key sang ID."
     value       = module.networking.public_subnet_ids
   }

   output "private_subnet_ids" {
     description = "Map private subnet key sang ID."
     value       = module.networking.private_subnet_ids
   }
   ```

   Không xuất credentials/secrets. Output resource IDs không phải secret nhưng state/output vẫn cần bảo vệ theo quyền truy cập của lab.

### Giai đoạn D — Format, validate và review plan

1. Từ đúng Terraform root `dev/lab/`, chạy:

   ```powershell
   terraform fmt -recursive
   terraform init
   terraform validate
   terraform plan
   ```

2. `terraform fmt` chuẩn hóa HCL. `terraform init` tải provider và khởi tạo backend đã cấu hình; không dùng `-reconfigure` hoặc migrate backend nếu chưa có kế hoạch. `terraform validate` kiểm tra cú pháp/cấu trúc; nó không xác minh CIDR với mạng ngoài AWS. `terraform plan` cho thấy các thay đổi dự kiến nhưng không tạo resource.

3. Đọc toàn bộ plan:

   - Provider đang dùng đúng account và Region; backend/state là `dev/lab/`.
   - Chỉ dự kiến tạo một VPC, bốn subnet, một IGW, hai route table, một route IPv4 default đến IGW và bốn subnet associations (cùng các outputs nếu có).
   - Hai public subnet nằm ở đúng hai AZ; hai private subnet cũng map theo cùng AZ tương ứng.
   - CIDR subnet nằm trong VPC, không overlap, và đã được đối chiếu với mạng ngoài AWS.
   - Public route table có `0.0.0.0/0 → IGW`; private table không có `0.0.0.0/0`.
   - Auto-assign public IPv4 tắt; không tạo EIP, NAT, endpoint, EC2, ALB, SG hoặc custom NACL.
   - Không có VPC/resource ngoài scope bị update, replace hoặc destroy.

4. Nếu plan có deletion/replacement, account/Region/state sai, hoặc CIDR chưa được xác nhận, dừng. Không dùng `terraform apply -target`, xóa state hoặc sửa tay resource để buộc plan thành công.

### Giai đoạn E — Triển khai và xác minh

1. Chỉ chạy `terraform apply` sau khi đã xác nhận account, Region, root module, backend/state, CIDR plan, phạm vi resource và chi phí. Đọc lại plan ngay trước khi chấp thuận apply.
2. Nếu không có phê duyệt hoặc chưa chắc backend/CIDR, dừng ở `terraform plan`; tài liệu và sơ đồ vẫn có thể được hoàn thành mà không tạo tài nguyên.
3. Sau apply, mở VPC Console và kiểm tra:
   - VPC CIDR/DNS settings đúng.
   - Bốn subnet ở CIDR/AZ dự kiến, auto-assign public IPv4 tắt.
   - IGW gắn với đúng VPC.
   - Public subnet associations trỏ đến public route table; bảng này có route `local` và `0.0.0.0/0` đến IGW.
   - Private subnet associations trỏ đến private route table; bảng này có route `local` nhưng không có default route đến IGW/NAT.
   - Default network ACL vẫn được dùng; lab không tạo custom NACL hoặc security group.
4. Chạy `terraform plan` lần nữa. Kết quả dự kiến là không có thay đổi cần thực hiện. Nếu có drift, xác định nguyên nhân trước khi sửa.
5. Không tạo EC2 chỉ để kiểm tra đường Internet. Route table thể hiện cấu hình control plane; không có workload nên lab chưa xác minh data-plane connection hoặc firewall/application behavior.

## 8. Xử lý sự cố

| Triệu chứng/thông báo | Nguyên nhân cần kiểm tra | Các bước chẩn đoán | Cách khắc phục an toàn |
|---|---|---|---|
| Subnet CIDR overlap hoặc AWS từ chối tạo subnet | CIDR không căn đúng, nằm ngoài VPC hoặc trùng subnet khác | So sánh VPC/subnet CIDR và inventory; kiểm tra block size/ranh giới CIDR | Chọn CIDR mới chưa dùng; không xóa subnet khác để lấy lại dải nếu chưa xác định owner |
| Availability Zone không khả dụng | AZ name không tồn tại/không được account hỗ trợ ở Region đã chọn | Kiểm tra Region/provider identity và AZ list trên Console | Chọn hai AZ trạng thái khả dụng trong cùng Region và cập nhật mapping CIDR có chủ đích |
| Public subnet không có route Internet | Association thiếu/sai, route không tạo được hoặc IGW chưa attach đúng VPC | Kiểm tra subnet association, route target và IGW attachment | Sửa association/route trong đúng module/state; chưa tạo EC2 để thử |
| Private subnet lại có default route | Có cấu hình ngoài scope, route table bị dùng chung sai hoặc thay đổi thủ công gây drift | Mở route table association và plan/state để xác định owner/nguồn thay đổi | Dừng apply; xác minh traffic phụ thuộc trước khi bỏ route; không xóa thủ công |
| `terraform init` không kết nối được backend | Backend chưa cấu hình, quyền thiếu hoặc backend key sai | Kiểm tra cấu hình backend, auth chain và state key; không gửi credentials vào logs/chat | Dùng quy trình backend đã phê duyệt, xác nhận đúng key dev/lab; không chuyển sang state khác tùy tiện |
| `terraform plan` hiển thị replace/destroy VPC/subnet | CIDR/name/key thay đổi, resource đã có ngoài state hoặc state không đúng | Xem address, plan reason, backend/workspace và tài nguyên Console | Dừng; lập migration/import/state plan an toàn; không apply để “thử xem” |
| VPC/subnet đã tạo nhưng Terraform báo lỗi association | Subnet đã gắn route table khác hoặc tài nguyên ngoài Terraform quản lý | Kiểm tra association trong Console/state và module ownership | Chuẩn hóa ownership trong một state; không để hai state quản lý cùng resource |
| VPC có route IGW nhưng workload không truy cập được Internet | Chưa có workload/public IPv4, SG/NACL/app chưa cho phép hoặc endpoint không public | Xác minh riêng route, địa chỉ, firewall, listener và service | Không kết luận từ route đơn lẻ; các phần workload/firewall sẽ được triển khai ở section sau |

## 9. Dọn dẹp và giữ lại tài nguyên

Tất cả VPC, subnet, IGW, route table, associations, outputs và state trong lab này là nền tảng dùng chung cho Sections 1–5. **Không chạy `terraform destroy` khi kết thúc lab hoặc giữa các section.** Không xóa riêng VPC/IGW/subnet bằng Console vì sẽ gây drift hoặc làm hỏng các lab tiếp theo.

Chỉ khi toàn bộ khóa/lab kết thúc và chủ sở hữu xác nhận mạng dev không còn được dùng, mới xem xét cleanup:

1. Xác nhận đúng thư mục `dev/lab/`, account dev, Region, backend và state; không áp dụng cho prod/capstone.
2. Kiểm kê toàn bộ tài nguyên trong state và Console, bao gồm các tài nguyên được section sau thêm vào VPC.
3. Xác nhận không còn compute, database, endpoint, dữ liệu hoặc tài nguyên nào phụ thuộc vào VPC.
4. Tạo destroy plan đầy đủ; review từng resource sẽ xóa, đánh giá dữ liệu và chi phí.
5. Chỉ chạy destroy sau khi có xác nhận rõ phạm vi và có phê duyệt phù hợp; sau đó xác minh resource đã xóa và theo dõi chi phí.

Prod không được destroy như quy trình dọn dẹp thông thường. Việc cleanup production cần kế hoạch thay đổi, phê duyệt, backup/DR và quy trình vận hành riêng.

## 10. Bài tập mở rộng và tiêu chí hoàn thành

### Bài tập mở rộng

1. Thay đổi Region/AZ nhưng giữ nguyên yêu cầu subnet không overlap. Trình bày cách xác minh AZ mapping trước khi sửa CIDR.
2. Vẽ thêm luồng cho một ALB public và một application private mà chưa tạo workload. Đánh dấu route, public addressing và security group/NACL nào sẽ cần được học/triển khai sau.
3. Giả sử application chỉ cần truy cập S3 và một API public khác. Đề xuất phần nào có thể dùng VPC endpoint, phần nào cần NAT/proxy, và những chi phí cần so sánh.
4. Thiết kế phương án prod riêng: số subnet theo AZ, cách tách route table, kiểm soát state/IAM và lý do không chỉ sao chép cấu hình dev.

### Tiêu chí hoàn thành

- Terraform plan chỉ chứa networking resources đã nêu trong phạm vi; không có workload hoặc tài nguyên tính phí ngoài dự kiến.
- CIDR VPC/subnet hợp lệ, không overlap và mapping subnet/AZ được ghi rõ.
- Public route table có đường IPv4 default đến IGW và chỉ associate với public subnets dự kiến.
- Private route table giữ route `local`, associate với private subnets và chưa có route mặc định ra Internet.
- Public IPv4 auto-assignment bị tắt; không có EIP, NAT Gateway, VPC endpoint hoặc compute resource.
- Người học giải thích được VPC, subnet, AZ, route table, IGW và giới hạn của public/private subnet theo cấu hình thực tế.
- State/backend của `dev/lab/` được giữ cho các section sau; không destroy hoặc chuyển state.

## Tổng kết lab và bước tiếp theo

Lab đã thiết lập một VPC dev hai AZ với hai public subnet và hai private subnet. Public route table có default route đến IGW; private route table chỉ có route nội bộ. Không tạo workload, vì vậy route chưa phải bằng chứng rằng ứng dụng có thể truy cập Internet. Public subnet cũng không tự động khiến mọi tài nguyên trong đó có public IPv4 hoặc được phép nhận traffic.

Giữ nguyên Terraform root module, backend/state và networking module này cho các section sau. Bài 4 có thể thêm NAT routing cho private subnet sau khi đánh giá chi phí và AZ; bài 5 bổ sung security groups theo luồng workload và phân tích NACL; bài 6 có thể thêm VPC endpoint cho dịch vụ được hỗ trợ. Sections 2–5 tiếp tục dùng cùng `dev/lab/` thay vì tạo root module/state mới.

Trước khi mở rộng, hãy tự giải thích: tại sao public và private subnet cần route table association riêng, vì sao private subnet hiện không thể đi Internet qua IGW, và cần kiểm tra những gì trước khi thêm NAT Gateway hoặc endpoint mà không làm gián đoạn các section tiếp theo?