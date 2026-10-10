# Section 1 — Bài 3: Internet Gateway và định tuyến cho public subnet

## Mục tiêu bài học

Sau bài này, người học có thể:

- Giải thích vai trò của Internet Gateway (IGW) và cách IGW kết nối một Amazon VPC với Internet qua định tuyến IPv4.
- Phân biệt IGW, route table, public IPv4 address, Elastic IP address, security group và network ACL.
- Đọc một route table để xác định subnet có tuyến mặc định IPv4 đến IGW hay không.
- Giải thích vì sao một route đến IGW chưa đủ để chứng minh tài nguyên trong subnet có thể truy cập Internet.
- Bổ sung IGW, route table, route `0.0.0.0/0` và các liên kết subnet bằng Terraform trong lab dùng chung, đồng thời kiểm tra plan trước khi áp dụng.
- Nhận biết tác động chi phí có thể phát sinh khi khởi chạy tài nguyên có public IPv4 address và tránh phá hủy state dùng chung của lab.

## 1. Bối cảnh và vấn đề

Một subnet có thể chứa tài nguyên cần nhận kết nối từ Internet, chẳng hạn một public-facing Application Load Balancer (ALB), hoặc một bastion host trong kiến trúc cũ. Để traffic IPv4 có thể đi giữa VPC và Internet, VPC cần được kết nối với Internet Gateway và các subnet cần route phù hợp.

Chỉ tạo một VPC hoặc đặt subnet tên `public` không tạo ra kết nối Internet. Cần có một chuỗi cấu hình nhất quán:

1. IGW được tạo và gắn vào đúng VPC.
2. Route table của subnet có route đến IGW cho đích IPv4 bên ngoài VPC.
3. Tài nguyên cần giao tiếp trực tiếp với Internet có địa chỉ public IPv4 phù hợp.
4. Security group, network ACL, cấu hình của dịch vụ và hệ điều hành cho phép traffic cần thiết.

Ví dụ, một ALB public có thể đặt trong các subnet ở nhiều Availability Zone (AZ). Route table của các subnet đó thường có tuyến mặc định IPv4 đến IGW. Tuy nhiên, nếu security group của ALB không cho phép traffic cần thiết, request vẫn bị chặn; nếu thiếu route hoặc IGW không gắn vào VPC, đường đi cũng không hoàn chỉnh.

Public subnet thường chỉ chứa các thành phần cần có đường định tuyến trực tiếp đến Internet. Compute và database không cần tiếp nhận kết nối trực tiếp từ Internet nên thường đặt trong private subnet, sau security group và các lớp bảo vệ phù hợp. Các workload private cần truy cập Internet đi ra thường dùng NAT Gateway hoặc VPC endpoints; các chủ đề đó sẽ được học riêng.

## 2. Khái niệm và thành phần cốt lõi

### Internet Gateway

Internet Gateway là thành phần do AWS quản lý, cho phép VPC giao tiếp với Internet khi route và địa chỉ của tài nguyên được cấu hình phù hợp. IGW có tính sẵn sàng và khả năng mở rộng do AWS quản lý; người dùng không phải tự vận hành một máy chủ gateway.

Một IGW:

- Được tạo trong một AWS Region và gắn với một VPC.
- Có thể được gắn với một VPC tại một thời điểm.
- Không tự tạo route trong route table.
- Không tự cấp public IPv4 address cho tài nguyên.
- Không thay thế security group, network ACL hoặc tường lửa của workload.

Đối với IPv4, IGW hỗ trợ ánh xạ giữa public IPv4 address của tài nguyên và private IPv4 address bên trong VPC. Tài nguyên cần public IPv4 address phù hợp để giao tiếp IPv4 trực tiếp với Internet qua IGW. Public IP gán tự động và Elastic IP address là các cách gán địa chỉ khác nhau; Elastic IP là địa chỉ IPv4 tĩnh được cấp phát riêng và có quy tắc chi phí riêng cần kiểm tra.

### Route table và route

Route table là tập các tuyến đường áp dụng cho một subnet hoặc một số subnet. Mỗi route có:

- **Destination:** dải CIDR đích, ví dụ `0.0.0.0/0`.
- **Target:** next hop hoặc thành phần nhận traffic, ví dụ `local`, IGW hay NAT Gateway.

Khi tạo VPC, AWS tự thêm route `local` để tài nguyên trong các CIDR của VPC có thể định tuyến nội bộ. Route `0.0.0.0/0` là default route IPv4: nó áp dụng cho các địa chỉ IPv4 đích không khớp với một route cụ thể hơn. AWS chọn route phù hợp nhất theo longest-prefix match; route cụ thể hơn thường được ưu tiên hơn route tổng quát.

Một route table có thể là **main route table** mặc định cho VPC hoặc một route table được liên kết tường minh với subnet. Với thiết kế production, thường nên thể hiện rõ route table và subnet association trong Terraform để người đọc biết subnet nào nhận route nào, thay vì dựa vào cấu hình ngầm định ngoài ý muốn.

### Public subnet

Trong ngữ cảnh định tuyến IPv4, subnet thường được gọi là public khi route table liên kết với subnet có route đến IGW cho traffic IPv4 bên ngoài VPC. Tuy nhiên, tài nguyên trong subnet chỉ có thể giao tiếp trực tiếp hai chiều với Internet nếu các điều kiện khác cũng thỏa:

- Tài nguyên có public IPv4 address hoặc một cấu hình public endpoint phù hợp.
- Route table có route đến IGW.
- Security group cho phép chiều traffic cần thiết.
- Network ACL không chặn chiều đi hoặc chiều về.
- Ứng dụng, hệ điều hành và cấu hình dịch vụ nhận/xử lý traffic.

Vì thế, “public subnet” mô tả đặc tính định tuyến của subnet; không đồng nghĩa mọi tài nguyên trong subnet đều được public hoặc an toàn để mở cho Internet.

### Public IPv4 address và Elastic IP address

Public IPv4 address là địa chỉ có thể định tuyến trên Internet. Trong VPC, tài nguyên thường đồng thời sử dụng private IPv4 address để giao tiếp nội bộ. IGW thực hiện ánh xạ giữa địa chỉ public và private theo cấu hình của AWS.

Các cách thường gặp để tài nguyên có public IPv4:

- Bật **auto-assign public IPv4** trên subnet; EC2 instance khởi chạy trong subnet có thể được tự động gán public IPv4 theo cấu hình.
- Gán public IPv4 khi khởi chạy instance, nếu loại instance và cấu hình hỗ trợ.
- Gán Elastic IP address khi cần một địa chỉ public IPv4 tĩnh phù hợp với kiến trúc.

Việc bật auto-assign public IPv4 cho subnet không tạo địa chỉ cho tất cả tài nguyên đang tồn tại; nó ảnh hưởng đến việc gán địa chỉ cho tài nguyên mới theo cấu hình và loại tài nguyên. Không bật public IP chỉ vì subnet có route đến IGW. Chỉ gán public IPv4 khi workload thật sự cần endpoint công khai và đã có biện pháp bảo vệ phù hợp.

### Security group và network ACL

Security group và network ACL kiểm soát traffic nhưng không tạo route:

- **Security group:** firewall stateful gắn với network interface/tài nguyên. Traffic phản hồi của kết nối được cho phép thường được theo dõi trạng thái; không cần tạo rule phản hồi đối xứng như với ACL stateless.
- **Network ACL:** firewall stateless ở cấp subnet. Cần xem cả rule chiều vào và chiều ra; traffic phản hồi cũng phải phù hợp với rule, thường bao gồm ephemeral ports cho một số kết nối.
- **Route table:** xác định traffic có đường đến target hay không; nó không tự cho phép traffic qua firewall.

### So sánh các thành phần trong đường đi

| Thành phần | Câu hỏi nó trả lời | Nó không làm gì |
|---|---|---|
| IGW | VPC có thành phần kết nối Internet IPv4 hay không? | Không tự tạo route, không cấp địa chỉ public và không lọc traffic theo ứng dụng |
| Route table | Traffic đến destination CIDR sẽ đi qua target nào? | Không thay thế security group hoặc network ACL |
| Public IPv4/EIP | Tài nguyên có địa chỉ IPv4 có thể định tuyến công khai nào? | Không tự tạo tuyến đường hoặc mở port |
| Security group | Traffic nào được phép đến/đi từ network interface? | Không tạo đường định tuyến |
| Network ACL | Traffic nào được phép vào/ra subnet theo rule stateless? | Không cấp địa chỉ IP hoặc route |
| Ứng dụng/hệ điều hành | Workload có lắng nghe và xử lý traffic không? | Không thể khắc phục route hoặc firewall bị chặn ở lớp mạng |

## 3. Cách hoạt động: route IPv4 từ public subnet đến Internet

Một request IPv4 đi từ tài nguyên trong subnet public tới Internet cần đi qua nhiều thành phần:

```text
Workload trong subnet
  │ private IPv4, public IPv4 phù hợp, traffic được cho phép
  ▼
Route table của subnet
  │ 0.0.0.0/0 → Internet Gateway
  ▼
Internet Gateway gắn với VPC
  │ ánh xạ public/private IPv4 theo cấu hình
  ▼
Internet
  │ response quay lại địa chỉ public
  ▼
IGW → route/stateful security rules → workload
```

### Bước 1: Workload tạo request

Workload gửi packet đến địa chỉ IPv4 bên ngoài VPC. Bên trong VPC, workload sử dụng private IPv4 address. Để giao tiếp trực tiếp với Internet qua IGW, workload cần có public IPv4 address hoặc endpoint public phù hợp với dịch vụ.

### Bước 2: Route table chọn đường đi

Route table liên kết với subnet kiểm tra destination. Nếu destination không thuộc route cụ thể hơn và route table có `0.0.0.0/0` trỏ đến IGW, route mặc định IPv4 này là candidate để gửi traffic ra ngoài VPC.

Nếu route table không có route tương ứng, không có next hop khả dụng hoặc route ở trạng thái lỗi/blackhole, request không đi được theo đường đó. Route `local` của VPC không thay thế default route đến Internet.

### Bước 3: IGW kết nối VPC với Internet

IGW phải ở trạng thái gắn vào đúng VPC. Khi route table trỏ đến IGW gắn với VPC, đây là đường định tuyến từ VPC ra Internet; IGW không tự chọn subnet và không tự mở port.

### Bước 4: Firewall và workload quyết định traffic có được chấp nhận không

Security group, network ACL và cấu hình ứng dụng phải cho phép traffic phù hợp. Ví dụ, một web listener có thể cần cho phép TCP 443 từ nguồn cần thiết. Không nên mở mọi port cho mọi nguồn nếu ứng dụng không yêu cầu.

### Bước 5: Response quay về

Response quay lại public address của endpoint và đi qua IGW về VPC. Stateful security group cho phép response thuộc kết nối đã được cho phép; network ACL là stateless nên rule chiều về cũng cần được cấu hình. Nếu route hoặc firewall ở một chiều không phù hợp, kết nối có thể timeout dù chiều gửi ban đầu có route.

## 4. Tư duy kiến trúc, bảo mật, chi phí và đánh đổi

### Tính sẵn sàng và khả năng phục hồi

IGW là thành phần được AWS quản lý, không phải một EC2 instance đơn lẻ cần người dùng tự scale hoặc tự đặt trong một AZ. Khi thiết kế VPC multi-AZ, mỗi public subnet trong từng AZ có thể liên kết với route table có route đến cùng IGW của VPC. Điều này tạo đường định tuyến ra ngoài cho các subnet, nhưng không tự triển khai workload dự phòng.

Khả năng phục hồi toàn hệ thống còn phụ thuộc vào:

- Workload có được triển khai trên nhiều AZ hay không.
- ALB, compute và database có cấu hình HA/failover phù hợp không.
- Security group và network ACL cho phép traffic giữa các thành phần cần thiết không.
- DNS, health checks, autoscaling và quy trình khôi phục có hoạt động đúng không.

Một IGW route là nền tảng kết nối, không phải kế hoạch Disaster Recovery. Không mô phỏng lỗi bằng cách gỡ IGW khỏi VPC dùng chung; hành động đó có thể làm gián đoạn mọi subnet sử dụng route qua IGW.

### Bảo mật

IGW làm cho đường định tuyến đến Internet khả dụng; việc endpoint có thể bị truy cập công khai còn phụ thuộc vào địa chỉ public, firewall, listener và dịch vụ. Hãy áp dụng các nguyên tắc sau:

- Chỉ đặt endpoint cần public trong subnet có định tuyến public; giữ application/database private trừ khi có yêu cầu được đánh giá rõ.
- Chỉ mở port cần thiết trong security group và giới hạn source phù hợp. Với website public, nguồn có thể là Internet; với quản trị, ưu tiên không mở SSH/RDP rộng ra `0.0.0.0/0`.
- Dùng TLS cho traffic ứng dụng công khai và quản lý certificate phù hợp.
- Rà soát cả network ACL, security group và firewall của hệ điều hành/ứng dụng.
- Không nhầm địa chỉ private với bảo vệ tuyệt đối; tài nguyên private vẫn cần least privilege và rule network phù hợp.
- Không dùng auto-assign public IPv4 đại trà cho workload không cần endpoint công khai.

### Chi phí

IGW và route table thường không có phí theo giờ riêng, nhưng phải kiểm tra bảng giá AWS hiện hành cho Region và loại sử dụng. Chi phí có thể phát sinh từ các phần liên quan, gồm:

- Public IPv4 address theo cơ chế tính giá hiện hành của AWS.
- Data transfer ra Internet hoặc giữa các dịch vụ/vùng.
- ALB, EC2, NAT Gateway hoặc tài nguyên khác được triển khai cùng kiến trúc.
- Elastic IP address theo trạng thái và cách gắn/sử dụng.

Không khởi chạy EC2 chỉ để xác nhận route trong bài này; việc cấp public IPv4 cho compute và để tài nguyên chạy có thể phát sinh phí. Bài thực hành Terraform bên dưới tạo networking cơ bản, không tạo compute. Trước khi apply, xem plan và bảng giá hiện hành; sau khi bắt đầu các section sau, đừng hủy lab dùng chung chỉ để dọn một bài.

### Lựa chọn kiến trúc và đánh đổi

- **IGW trực tiếp cho workload public:** Phù hợp với endpoint cần được khách hàng truy cập trực tiếp, chẳng hạn ALB public. Cần bảo vệ listener, TLS, security group và các thành phần ứng dụng.
- **Private workload đi ra qua NAT Gateway:** Giữ workload không nhận kết nối Internet khởi tạo trực tiếp, nhưng vẫn có thể cho phép kết nối outbound theo route. NAT Gateway có chi phí và là chủ đề bài kế tiếp; nó không thay IGW cho public endpoint.
- **VPC endpoints:** Có thể cung cấp đường kết nối riêng đến một số dịch vụ AWS, tránh một số traffic phải đi qua Internet/NAT. Endpoint chỉ hỗ trợ các dịch vụ/kiểu kết nối nhất định và có cấu hình/chi phí riêng.
- **Bật auto-assign public IPv4:** Dễ dùng cho một số lab, nhưng tài nguyên mới trong subnet có thể nhận public IPv4 ngoài dự kiến và phát sinh phí. Dùng khi có mục tiêu rõ ràng, nếu không thì gán địa chỉ có chủ đích.
- **Dùng IGW làm “firewall”:** Không phù hợp. IGW là thành phần kết nối/định tuyến, không phải bộ lọc ứng dụng; cần security group, network ACL và kiểm soát ở tầng dịch vụ.

### IPv6 khác IPv4

Bài này cấu hình default route IPv4 `0.0.0.0/0`. IPv6 dùng dải và route khác, thường là `::/0`; mô hình IPv6 public/private không thể suy ra y hệt chỉ từ việc có một địa chỉ IPv6 toàn cục. Với outbound-only IPv6 trong subnet không nhận kết nối khởi tạo từ Internet, có thể cần egress-only Internet Gateway. Không thêm route IPv6 vào lab nếu chưa cấp và thiết kế IPv6 CIDR cùng firewall rules một cách rõ ràng.

## 5. Quan sát trên AWS Management Console

Phần này chỉ xem VPC, subnet, IGW và route table hiện có. Không tạo, gắn, tách hoặc xóa network resource. Bố cục Console có thể thay đổi; nếu menu khác, dùng thanh tìm kiếm để mở **VPC**.

1. **Xác nhận account và Region.** Đăng nhập bằng danh tính được cấp, kiểm tra AWS account và Region đang chọn. VPC là tài nguyên theo Region; cần đảm bảo bạn đang xem đúng Region.
2. **Mở danh sách VPC.** Trong VPC Console, vào danh sách VPC và chọn một VPC mà bạn được phép đọc. Ghi lại VPC ID và CIDR ở ghi chú riêng tư; không chia sẻ topology nội bộ công khai.
3. **Quan sát Internet Gateways.** Mở mục **Internet Gateways** và tìm IGW có attachment đến VPC đã chọn. Kiểm tra attachment state và VPC ID. Nếu không có IGW, chỉ ghi nhận; không tạo hoặc gắn IGW trong phần Console.
4. **Mở Subnets.** Lọc các subnet thuộc VPC đó. Ghi subnet ID, CIDR, AZ và tên tag nếu có. Tên tag chỉ là nhãn, không đủ chứng minh subnet là public.
5. **Xác định route table association.** Từ subnet, xem route table liên kết; nếu không có liên kết explicit, kiểm tra main route table của VPC. Ghi lại route table ID và các destination/target.
6. **Đọc route IPv4.** Tìm `0.0.0.0/0`. Nếu target là một IGW đang gắn với đúng VPC, route table có default route IPv4 hướng đến Internet Gateway. Nếu không có route này, subnet không có tuyến mặc định IPv4 trực tiếp đến Internet qua IGW.
7. **Kiểm tra thêm các điều kiện.** Chỉ ở chế độ đọc, xem subnet setting auto-assign public IPv4, public address của tài nguyên mẫu nếu có, security group và network ACL. Không kết luận rằng request Internet chắc chắn thành công chỉ từ route table.
8. **Ghi kết luận có giới hạn.** Nêu điều gì được chứng minh bởi route và điều gì còn phụ thuộc vào public IP, firewall, listener, DNS hoặc cấu hình khác. Không sửa route, association, IGW attachment hay subnet settings.

Nếu account không có VPC tùy chỉnh hoặc bạn không đủ quyền xem, dùng sơ đồ luồng ở phần 3 để phân tích. Không xin quyền quản trị rộng hơn chỉ để hoàn thành bài.

## 6. Thực hành

> **Mục tiêu:** Bổ sung Internet Gateway và tuyến mặc định IPv4 cho hai public subnet trong networking module dùng chung, rồi kiểm tra Terraform plan trước khi triển khai.  
> **Môi trường:** Cấu hình ví dụ áp dụng trong `dev/lab/`. `prod/lab/` có state và giá trị CIDR riêng; không triển khai prod trong lần thực hành đầu tiên.  
> **Chi phí dự kiến:** Networking resource trong ví dụ thường không có phí theo giờ riêng như compute, nhưng public IPv4 address, data transfer và tài nguyên được thêm ở các bài sau có thể phát sinh phí. Xác minh bảng giá AWS hiện hành trước khi apply. Không tạo EC2/ALB trong bài này.  
> **Rủi ro và phạm vi:** Đây là lab dùng chung xuyên Sections 1–5. Không tạo root module hoặc state riêng cho Bài 3. Nếu `dev/lab/` đã có VPC từ bài khác, tích hợp các resource vào networking module hiện có và không tạo VPC trùng. Không chạy `terraform destroy` trên lab dùng chung.

### Kiến trúc lab

Lab giả định module networking tạo một VPC dev `10.20.0.0/16` và hai public subnet:

- AZ thứ nhất: `10.20.0.0/24`.
- AZ thứ hai: `10.20.1.0/24`.

Module sẽ gắn một IGW vào VPC, tạo route table public với route `0.0.0.0/0` đến IGW, rồi associate cả hai subnet với route table này. Module có biến để bật hoặc tắt auto-assign public IPv4; trong cấu hình mẫu bên dưới, giá trị là `false` để các EC2 được khởi chạy sau này không tự động nhận public IPv4. Nếu một lab được phê duyệt cần minh họa auto-assign, bật biến có chủ đích và tính cả chi phí địa chỉ public.

```text
dev/lab/ (root module và state dùng chung)
└── modules/networking/
    ├── main.tf
    │   ├── VPC
    │   ├── public subnets ở hai AZ
    │   ├── Internet Gateway
    │   ├── public route table và 0.0.0.0/0 → IGW
    │   └── subnet associations
    ├── variables.tf
    └── outputs.tf
```

Không tạo thêm module nếu networking module đã tồn tại; thêm các resource vào module hiện có theo cách tương thích với VPC/subnet do bài trước hoặc lab hiện tại quản lý. CIDR minh họa phải khớp với bản quy hoạch đã được xác minh ở Bài 2.

### Điều kiện trước khi bắt đầu

- Terraform đã được cài đặt và AWS provider đã được cấu hình ở root module `dev/lab/`.
- Region được chọn có ít nhất hai Availability Zone ở trạng thái khả dụng trong account; module ví dụ lấy hai AZ đầu tiên từ AWS provider data source. Với môi trường cần mapping ổn định giữa nhiều account, chọn AZ theo AZ ID hoặc theo quy ước mạng của tổ chức.
- Có quyền AWS tối thiểu cần thiết để đọc trạng thái hiện tại và tạo/đọc VPC, subnet, Internet Gateway, route table và association nếu bạn quyết định apply. Quyền cần thiết phụ thuộc vào policy của account; không dùng administrator access mặc định.
- Xác nhận account, Region, working directory, backend và state đang trỏ đến `dev/lab/`. Không dựa vào tên profile hoặc thư mục hiện tại mà không kiểm tra.
- Đã đối chiếu CIDR `10.20.0.0/16`, `10.20.0.0/24` và `10.20.1.0/24` với bản quy hoạch mạng và mọi dải cần kết nối.
- Đã đọc chi phí public IPv4 hiện hành; chưa có EC2 hoặc ALB trong lab này.
- Không đặt AWS access key, secret key hoặc giá trị nhạy cảm trong source code, `terraform.tfvars` hoặc Terraform backend configuration.

### Các bước thực hiện

1. **Kiểm tra root module dùng chung.** Từ thư mục dự án, mở `dev/lab/` và kiểm tra các file `main.tf`, `providers.tf`, `variables.tf`, `outputs.tf` cùng module networking hiện có. Nếu root module hoặc VPC đã được tạo ở bài/lab trước, tái sử dụng chúng; không khởi tạo một thư mục Terraform riêng cho bài này.
2. **Chuẩn bị module call.** Nếu module networking chưa được gọi từ root, thêm một module call tương đương vào `dev/lab/main.tf`. Thay CIDR và source theo module thực tế:

   ```hcl
   module "networking" {
     source = "./modules/networking"

     environment_name          = "dev"
     vpc_cidr                  = var.vpc_cidr
     public_subnet_cidrs       = var.public_subnet_cidrs
     map_public_ip_on_launch   = var.map_public_ip_on_launch
   }
   ```

   HCL trên là ví dụ về giao diện root-to-module. Nếu `module "networking"` đã có, chỉ cập nhật input cần thiết; không khai báo trùng một module block cùng tên. Root module cần định nghĩa biến tương ứng trong `variables.tf`, ví dụ:

   ```hcl
   variable "vpc_cidr" {
     description = "CIDR IPv4 đã được quy hoạch cho VPC dev."
     type        = string
   }

   variable "public_subnet_cidrs" {
     description = "CIDR của hai public subnet trong VPC dev."
     type        = list(string)
   }

   variable "map_public_ip_on_launch" {
     description = "Có tự động gán public IPv4 cho tài nguyên mới trong public subnet hay không."
     type        = bool
     default     = false
   }
   ```

3. **Khai báo input module.** Trong `modules/networking/variables.tf`, khai báo các input cần thiết. Ví dụ:

   ```hcl
   variable "environment_name" {
     description = "Tên môi trường dùng trong tên và tag của tài nguyên."
     type        = string
   }

   variable "vpc_cidr" {
     description = "CIDR IPv4 của VPC."
     type        = string

     validation {
       condition     = can(cidrhost(var.vpc_cidr, 0))
       error_message = "vpc_cidr phải là một IPv4 CIDR hợp lệ."
     }
   }

   variable "public_subnet_cidrs" {
     description = "Hai CIDR IPv4 không chồng lấn cho public subnet của lab."
     type        = list(string)

     validation {
       condition     = length(var.public_subnet_cidrs) == 2
       error_message = "Lab này cần đúng hai public subnet để minh họa hai AZ."
     }

     validation {
       condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
       error_message = "Mỗi phần tử của public_subnet_cidrs phải là IPv4 CIDR hợp lệ."
     }
   }

   variable "map_public_ip_on_launch" {
     description = "Có tự động gán public IPv4 cho tài nguyên mới hỗ trợ trong subnet hay không."
     type        = bool
     default     = false
   }
   ```

   Các validation trên kiểm tra CIDR hợp lệ và số lượng subnet, nhưng không chứng minh CIDR subnet nằm trong VPC hoặc không overlap. Hãy kiểm tra các điều kiện đó trong bản quy hoạch và xác minh lại trong plan/provider error trước khi apply.

4. **Tạo hoặc cập nhật networking resources.** Trong `modules/networking/main.tf`, giữ hoặc tạo VPC và public subnet theo CIDR đã được phê duyệt. Ví dụ dưới đây giả định module đang chịu trách nhiệm tạo VPC và hai public subnet:

   ```hcl
   data "aws_availability_zones" "available" {
     state = "available"
   }

   locals {
     public_subnets = {
       for index, cidr in var.public_subnet_cidrs :
       tostring(index) => {
         cidr = cidr
         az   = data.aws_availability_zones.available.names[index]
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
     map_public_ip_on_launch = var.map_public_ip_on_launch

     tags = {
       Name        = "${var.environment_name}-public-${each.key}"
       Environment = var.environment_name
       Network     = "public"
     }
   }

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

   resource "aws_route_table_association" "public" {
     for_each = aws_subnet.public

     subnet_id      = each.value.id
     route_table_id = aws_route_table.public.id
   }
   ```

   Nếu VPC và subnet đã do resource/module khác quản lý, không thêm `aws_vpc.this` hoặc `aws_subnet.public` trùng lặp. Thay vào đó, cung cấp VPC ID và subnet IDs hiện có cho module/phần cấu hình phù hợp, rồi chỉ quản lý IGW, route table, route và association còn thiếu. Không quản lý cùng một AWS resource từ hai Terraform state.

5. **Khai báo outputs để phần lab sau có thể tái sử dụng.** Trong `modules/networking/outputs.tf`, xuất thông tin cần cho root module hoặc module khác mà không xuất credentials/secrets:

   ```hcl
   output "vpc_id" {
     description = "ID của VPC do networking module quản lý."
     value       = aws_vpc.this.id
   }

   output "internet_gateway_id" {
     description = "ID của Internet Gateway gắn với VPC."
     value       = aws_internet_gateway.this.id
   }

   output "public_subnet_ids" {
     description = "Map subnet key sang ID của public subnet."
     value       = { for key, subnet in aws_subnet.public : key => subnet.id }
   }

   output "public_route_table_id" {
     description = "ID route table liên kết với các public subnet."
     value       = aws_route_table.public.id
   }
   ```

   Nếu module tái sử dụng VPC/subnet hiện có, chỉnh outputs theo resource thực tế. Không tạo output trỏ đến resource không do module quản lý.

6. **Tạo file biến cục bộ an toàn.** Ở root `dev/lab/`, khai báo các biến cần thiết trong `variables.tf` và tạo `terraform.tfvars` cục bộ, không commit file này. Ví dụ cho cấu hình minh họa:

   ```hcl
   vpc_cidr            = "10.20.0.0/16"
   public_subnet_cidrs = ["10.20.0.0/24", "10.20.1.0/24"]

   # Chỉ đặt true khi lab cần auto-assign public IPv4 và đã kiểm tra chi phí.
   map_public_ip_on_launch = false
   ```

   Giá trị `false` được chọn để không mặc định gán public IPv4 cho compute mới trong bài học này. Nếu cần thử cơ chế auto-assign ở một lab có EC2 được phê duyệt, bật có chủ đích và tính cả chi phí địa chỉ public.

7. **Định dạng và xác thực cấu hình.** Từ root `dev/lab/`, chạy:

   ```powershell
   terraform fmt -recursive
   terraform init
   terraform validate
   ```

   `terraform init` khởi tạo provider/backend theo cấu hình root hiện tại. Không thay backend của lab dùng chung hoặc dùng một state khác với state được dự án quy định. Nếu init báo backend chưa cấu hình, dừng lại và hoàn tất lựa chọn backend an toàn theo hướng dẫn dự án; không đưa thông tin đăng nhập vào file Terraform.

8. **Tạo và đọc execution plan.** Chạy:

   ```powershell
   terraform plan
   ```

   Đảm bảo plan sử dụng đúng `dev/lab/` và chỉ tạo/cập nhật tài nguyên dự kiến. Kiểm tra VPC/subnet không bị thay thế ngoài ý muốn, IGW gắn đúng VPC, route `0.0.0.0/0` trỏ đến IGW và associations nhắm đúng public subnets. Nếu plan muốn xóa tài nguyên dùng chung, thay CIDR hiện có, tạo một VPC thứ hai không cần thiết hoặc hiển thị thay đổi không hiểu rõ, không apply; điều tra nguyên nhân trước.

9. **Quyết định có áp dụng hay không.** Nếu đây là AWS account/lab được phép, CIDR đã xác minh, chi phí đã được kiểm tra và plan đúng, người học có thể chạy:

   ```powershell
   terraform apply
   ```

   Đọc lại plan mà Terraform trình bày khi yêu cầu xác nhận. Chỉ xác nhận nếu nó khớp với thay đổi đã duyệt. Nếu chưa có quyền hoặc chưa chắc về backend/state/chi phí, dừng sau `terraform plan`; mục tiêu học route có thể hoàn thành bằng plan và sơ đồ mà không cần tạo tài nguyên.

10. **Ghi nhận thông tin để nối tiếp lab.** Lưu outputs và ghi lại VPC ID, public subnet IDs, IGW ID và route table ID theo quy trình dự án. Các section sau phải tham chiếu networking module/state dùng chung, không khai báo lại cùng VPC hoặc tạo một root module riêng cho section.

### Xác minh kết quả

Sau `terraform plan` hoặc `terraform apply`, xác minh các điều kiện sau:

- Có đúng một IGW được gắn với đúng VPC của môi trường dev.
- Public route table thuộc VPC đó và có route `0.0.0.0/0` với target là IGW tương ứng.
- Mỗi public subnet được associate với route table đúng; không chỉ dựa vào tên/tag.
- Route table còn local route cho CIDR VPC và không có thay đổi bất ngờ với route khác.
- Auto-assign public IPv4 đang ở trạng thái mong muốn; trong ví dụ, giá trị là `false`.
- Không có EC2, ALB, Elastic IP hoặc tài nguyên tính phí nào được tạo bởi các đoạn cấu hình của bài này.
- `terraform plan` kế tiếp không đề xuất thay đổi nếu không sửa cấu hình; đây là cách kiểm tra cấu hình và state đang đồng bộ.

Nếu đã apply và được phép dùng Console, kiểm tra **Internet Gateways**, **Route tables** và **Subnet associations** ở chế độ chỉ đọc. Đừng thử kết nối Internet bằng cách tạo một EC2 ngẫu nhiên; việc kiểm tra đó có thể phát sinh chi phí và cần một kế hoạch bảo mật riêng.

Quan trọng: việc các điều kiện trên đúng chỉ chứng minh cấu hình route cơ bản. Chưa thể kết luận một ứng dụng có thể truy cập Internet hoặc được Internet truy cập nếu chưa có tài nguyên với public endpoint, security group/network ACL phù hợp, listener/ứng dụng đang chạy và DNS/TLS được cấu hình.

### Xử lý lỗi thường gặp

| Triệu chứng | Nguyên nhân có thể có | Cách kiểm tra và khắc phục |
|---|---|---|
| Route table có `0.0.0.0/0` nhưng subnet không đi Internet được | Target không phải IGW đang gắn đúng VPC; subnet association sai; tài nguyên không có public IP; hoặc firewall chặn | Kiểm tra route target, IGW attachment, subnet association, public address và security group/network ACL theo từng lớp |
| Terraform báo không thể gắn IGW | IGW đã gắn vào VPC khác hoặc cấu hình/state đang quản lý resource không nhất quán | Kiểm tra attachment và state; không xóa IGW chưa xác định chủ sở hữu |
| Terraform tạo route nhưng AWS báo target không hợp lệ | IGW không thuộc cùng VPC với route table hoặc ID tham chiếu sai | So sánh VPC ID của IGW, route table và subnet; sửa dependency/input thay vì hard-code ID không đúng |
| Subnet không được associate với route table dự kiến | Association thiếu, subnet đang dùng main route table, hoặc một association khác bị khai báo | Kiểm tra subnet association trong plan và Console; bảo đảm mỗi subnet dùng route table dự định |
| Hai resource tạo cùng một route table association | Cấu hình module lặp hoặc hai root state đang cùng quản lý subnet | Chỉ một Terraform state nên quản lý mỗi association; nhập/di chuyển state theo quy trình an toàn, không xóa state tùy tiện |
| Request inbound bị timeout dù route outbound có vẻ đúng | Security group, network ACL, public endpoint, listener hoặc ứng dụng không cho phép | Kiểm tra chiều vào và chiều về; network ACL stateless nên cần rule tương ứng cho response |
| Instance mới nhận public IPv4 ngoài dự kiến | `map_public_ip_on_launch` bật trên subnet hoặc launch config yêu cầu public IP | Kiểm tra subnet attribute và cấu hình launch; tắt auto-assign nếu không cần, rồi kiểm tra giá public IPv4 hiện hành |
| `terraform plan` đề xuất thay thế VPC/subnet trong lab dùng chung | Đổi CIDR hoặc địa chỉ resource/state không khớp | Không apply; xác định resource đã tồn tại và state đúng, rồi điều chỉnh cấu hình theo kế hoạch migration |

### Dọn dẹp tài nguyên

Đây là lab dùng chung xuyên Sections 1–5. Không chạy `terraform destroy` sau Bài 3, vì thao tác đó có thể xóa VPC, subnet hoặc tài nguyên từ các bài sau đang dùng cùng state. Giữ IGW và public route table để tiếp tục học NAT Gateway, security group, compute và các thành phần khác.

Nếu cần hủy toàn bộ lab dev sau khi hoàn thành khóa:

1. Xác nhận thư mục root, backend, workspace và account thật sự là môi trường lab dev.
2. Kiểm tra tài nguyên dữ liệu hoặc tài nguyên có deletion protection cần xử lý riêng.
3. Đọc toàn bộ plan destroy và xác nhận không ảnh hưởng prod hoặc tài nguyên ngoài lab.
4. Chỉ thực hiện destroy theo quy trình đã được chủ sở hữu phê duyệt; không dùng `-target` như cách dọn dẹp thông thường.

Không sửa `prod/lab/` hoặc chạy destroy trên prod như một phần của bài này.

## 7. Bài tập tự kiểm tra

Trả lời bằng cách lần theo từng lớp của đường đi. Phân biệt điều mà route chứng minh với điều vẫn cần xác minh ở resource, firewall hoặc ứng dụng.

1. Một subnet có tên `public-app` nhưng route table chỉ có local route. Có thể gọi nó là public subnet theo định nghĩa định tuyến IPv4 trong bài này không? Giải thích.
2. Một subnet có route `0.0.0.0/0 → IGW`, nhưng EC2 instance không có public IPv4. Điều gì đã được cấu hình và điều gì còn thiếu để instance giao tiếp trực tiếp với Internet?
3. Vì sao IGW không thay security group hoặc network ACL? Mô tả trách nhiệm của từng thành phần trong một request HTTPS inbound.
4. Một route table có `0.0.0.0/0 → IGW`, nhưng security group không cho phép TCP 443. Request HTTPS có được ứng dụng nhận không? Giải thích luồng.
5. Security group cho phép inbound TCP 443, nhưng subnet không có route đến IGW và endpoint không có đường public khác. Vì sao security group rule không đủ?
6. So sánh IGW và NAT Gateway theo hướng traffic khởi tạo và loại subnet thường sử dụng. Vì sao bài sau cần NAT Gateway dù VPC đã có IGW?
7. Một route table được gắn vào hai public subnet ở hai AZ. Liệt kê những gì tuyến `0.0.0.0/0 → IGW` chứng minh và ít nhất ba điều nó không chứng minh.
8. Vì sao không nên chạy `terraform destroy` sau bài này trong khi networking lab dùng chung state cho các bài tiếp theo?

### Gợi ý đáp án

1. Không. Tên subnet chỉ là tag. Nếu route table liên kết không có tuyến IPv4 trực tiếp đến IGW, thì theo định nghĩa định tuyến của bài này, subnet không có đường public IPv4 trực tiếp qua IGW. Cần xem route table thực tế và association, không suy luận từ nhãn.
2. Route table đã có hướng gửi traffic IPv4 không khớp route cụ thể hơn đến IGW, nhưng EC2 không có địa chỉ public IPv4 để thiết lập giao tiếp Internet trực tiếp theo mô hình này. Cũng cần kiểm tra security group, network ACL, OS firewall và ứng dụng. Không nên gán public IP nếu kiến trúc không yêu cầu.
3. IGW cung cấp kết nối/định tuyến giữa VPC và Internet. Route table chọn IGW làm next hop. Security group cho phép traffic ở network interface; network ACL áp dụng rule stateless ở subnet. Ứng dụng cần listener HTTPS hoạt động và certificate/TLS được cấu hình. Thiếu bất kỳ lớp cần thiết nào đều có thể làm request thất bại.
4. Không. Route đưa packet đến IGW, nhưng security group không cho TCP 443 nên traffic inbound bị chặn trước khi được ứng dụng xử lý. Routing và filtering là hai trách nhiệm khác nhau.
5. Security group chỉ cho phép hoặc từ chối traffic khi traffic đến network interface; nó không tạo route. Nếu không có đường đi đến endpoint và đường response, request không thể đến instance dù rule firewall cho phép.
6. IGW hỗ trợ đường trực tiếp giữa VPC và Internet cho endpoint public có cấu hình phù hợp. NAT Gateway thường cho phép workload trong private subnet khởi tạo kết nối outbound qua NAT, trong khi Internet không khởi tạo kết nối trực tiếp đến private address qua NAT. NAT Gateway thường cần route đến IGW ở phía public subnet và có chi phí riêng; chi tiết thuộc bài tiếp theo.
7. Route chứng minh route table có default IPv4 target IGW và các subnet association dùng route table đó. Nó không chứng minh resource có public IP, security group cho phép, network ACL cho phép response, ứng dụng đang lắng nghe, DNS/TLS đúng hoặc mọi request chắc chắn thành công.
8. Vì `dev/lab/` là root module/state xuyên nhiều section. Destroy có thể xóa networking mà section sau cần, đồng thời có thể tác động mọi resource khác cùng state. Dọn dẹp phải xem toàn bộ plan và chỉ thực hiện sau khi lab hoàn tất, đúng account/backend/state và đã xác nhận phạm vi.

## Tổng kết kiến thức và nguyên tắc áp dụng

Internet Gateway là thành phần kết nối VPC với Internet; route table phải hướng traffic IPv4 phù hợp đến IGW. Một public subnet là subnet có đường định tuyến trực tiếp đến IGW, nhưng subnet đó không tự làm mọi tài nguyên trở nên public. Tài nguyên cần public IPv4 address hoặc endpoint tương ứng; firewall, ứng dụng, DNS và TLS cũng phải được cấu hình.

Khi chẩn đoán kết nối, lần lượt kiểm tra route table và subnet association, IGW attachment, public address, security group, network ACL, listener và response path. Đừng nhầm “có route” với “được phép”, hoặc “subnet có đường Internet” với “mọi resource trong subnet có thể truy cập Internet”.

Trong dự án này, network module thuộc root module dùng chung `dev/lab/` và `prod/lab/`. Các section sau cần mở rộng module/state đó, không tạo VPC hoặc Terraform state trùng. Sau Bài 3, giữ networking để tiếp tục; không destroy lab giữa các section. Trước khi cấp public IPv4 hoặc triển khai compute, kiểm tra chi phí hiện hành và xác nhận endpoint thật sự cần công khai.

Khi xem xét một subnet mới, hãy hỏi: “Route table nào đang áp dụng?”, “IGW có gắn đúng VPC không?”, “Resource có public endpoint cần thiết không?”, “Firewall có chỉ cho phép traffic cần thiết không?”, và “Có cách nào giữ workload private mà vẫn đáp ứng use case không?”
