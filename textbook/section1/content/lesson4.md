# Section 1 — Bài 4: NAT Gateway và định tuyến cho private subnet

## Mục tiêu bài học

Sau bài này, người học có thể:

- Giải thích vì sao một workload trong private subnet có thể cần khởi tạo kết nối đi ra ngoài mà không cần nhận kết nối khởi tạo trực tiếp từ Internet.
- Mô tả vai trò của NAT Gateway (Network Address Translation Gateway), Elastic IP address, Internet Gateway và route table trong đường đi IPv4 từ private subnet ra Internet.
- Đọc route table để phân biệt tuyến mặc định của public subnet trỏ đến Internet Gateway với tuyến mặc định của private subnet trỏ đến NAT Gateway.
- Giải thích giới hạn phạm vi Availability Zone của NAT Gateway, rủi ro cross-AZ và sự khác nhau giữa một NAT Gateway dùng chung với NAT Gateway riêng cho từng AZ.
- So sánh NAT Gateway với NAT instance, VPC endpoint và egress-only Internet Gateway để chọn phương án theo loại traffic, khả năng sẵn sàng, bảo mật và chi phí.
- Mở rộng networking module trong Terraform root module dùng chung `dev/lab/` để tạo private subnet và NAT routing, đọc plan trước khi áp dụng, đồng thời tránh quản lý trùng resource hoặc phá hủy state dùng chung.
- Xác định các khoản phí có thể phát sinh và những bước cần kiểm tra trước khi tạo NAT Gateway.

## 1. Bối cảnh và vấn đề

Một máy chủ ứng dụng hoặc container thường cần tải package, gọi API bên ngoài, lấy image từ registry hoặc gửi dữ liệu đến dịch vụ khác. Tuy nhiên, không phải vì workload cần khởi tạo kết nối đi ra ngoài mà nó cũng cần có public IPv4 address hoặc nhận kết nối khởi tạo trực tiếp từ Internet.

Đây là mục đích của private subnet: giữ workload không có đường định tuyến trực tiếp đến Internet Gateway, đồng thời có thể cung cấp một đường đi outbound được kiểm soát. Với IPv4, một cách phổ biến là định tuyến traffic từ private subnet qua NAT Gateway đặt trong public subnet. NAT Gateway dùng địa chỉ public IPv4 để gửi traffic ra ngoài thay cho các địa chỉ private của workload.

Ví dụ, một ECS task hoặc EC2 instance trong application-private subnet cần tải bản cập nhật từ một endpoint Internet. Luồng outbound có thể đi qua NAT Gateway, nhưng một máy chủ trên Internet không thể chỉ vì vậy mà mở kết nối mới tùy ý vào task hoặc instance đó. Security group, network ACL, ứng dụng và cấu hình định tuyến vẫn quyết định traffic nào được phép.

NAT Gateway hữu ích nhưng không miễn phí và không phải lựa chọn mặc định cho mọi traffic. Nếu workload chỉ cần gọi các dịch vụ AWS được hỗ trợ, VPC endpoint có thể cung cấp đường truy cập riêng, giảm phụ thuộc vào NAT và có thể giảm một số chi phí data processing. Nếu cần IPv6 outbound-only, egress-only Internet Gateway là thành phần tương ứng; NAT Gateway không phải cơ chế chuyển tiếp IPv6.

## 2. Khái niệm và thành phần cốt lõi

### Private subnet và giới hạn của route table

Subnet không trở thành private chỉ vì tên của nó có chữ `private`, hoặc vì CIDR của nó thuộc dải IPv4 private. Trong bài này, một subnet được xem là private theo kiến trúc khi route table của subnet không có tuyến trực tiếp đến Internet Gateway. Thay vào đó, route table có thể có tuyến đến NAT Gateway cho traffic IPv4 outbound.

Private subnet thường vẫn có route `local` để giao tiếp nội bộ trong VPC. Vì vậy, “private” không có nghĩa là bị cô lập hoàn toàn hoặc không thể giao tiếp với bất kỳ mạng nào. Nó mô tả cách subnet được định tuyến; security group, network ACL, IAM, cấu hình dịch vụ và các kết nối khác tiếp tục áp dụng.

### NAT và NAT Gateway

**Network Address Translation (NAT)** là quá trình thay đổi địa chỉ IP nguồn hoặc đích của packet khi chuyển tiếp. Khi một workload có private IPv4 address khởi tạo kết nối đi qua public NAT Gateway, NAT Gateway thay địa chỉ nguồn private bằng địa chỉ public IPv4 của nó. NAT Gateway duy trì trạng thái kết nối để response thuộc kết nối đó có thể được chuyển trả về đúng workload khởi tạo.

**NAT Gateway** là dịch vụ NAT được AWS quản lý. Một public NAT Gateway được tạo trong một public subnet và dùng Elastic IP address (EIP). Public subnet của NAT Gateway cần có đường IPv4 mặc định đến Internet Gateway để NAT Gateway có thể chuyển traffic tới Internet. Mỗi private subnet cần có route phù hợp trỏ đến NAT Gateway.

NAT Gateway:

- Cho phép workload phía sau nó khởi tạo kết nối outbound theo giao thức được hỗ trợ.
- Cho phép response của kết nối outbound đã được NAT xử lý quay lại workload tương ứng.
- Không cho phép một bên Internet tùy ý khởi tạo kết nối mới đến workload private phía sau NAT.
- Không thay thế security group, network ACL, firewall của workload, proxy ứng dụng, IAM hoặc cơ chế lọc nội dung.
- Được AWS quản lý, nhưng là resource có phạm vi một Availability Zone (AZ); cần tính AZ vào thiết kế sẵn sàng.

### Public NAT Gateway và private NAT Gateway

Hai kiểu NAT Gateway có mục đích khác nhau:

| Kiểu NAT Gateway | Vị trí và địa chỉ | Mục tiêu định tuyến | Lưu ý |
|---|---|---|---|
| Public NAT Gateway | Đặt trong public subnet và gắn EIP | Cho private IPv4 workload đi đến Internet hoặc mạng đích có route phù hợp | Public subnet cần tuyến đến IGW; mỗi gateway phát sinh chi phí theo cách sử dụng. |
| Private NAT Gateway | Đặt trong subnet và không dùng EIP public như public NAT | Dùng để NAT traffic giữa các mạng riêng có kết nối/định tuyến phù hợp | Không cung cấp đường ra Internet; cần thiết kế kết nối mạng đích riêng. |

Bài này tập trung vào public NAT Gateway cho outbound IPv4 Internet. Không tạo private NAT Gateway vì luồng mạng riêng giữa VPC, VPN, Direct Connect hoặc Transit Gateway nằm ngoài phạm vi bài tập.

### Route table và các tuyến quan trọng

Route table của public subnet thường có:

```text
VPC CIDR      → local
0.0.0.0/0     → Internet Gateway
```

Route table của private subnet dùng public NAT Gateway thường có:

```text
VPC CIDR      → local
0.0.0.0/0     → NAT Gateway
```

Default route `0.0.0.0/0` chỉ áp dụng cho IPv4 destination không khớp với route cụ thể hơn. Route `local` vẫn được giữ để traffic nội bộ VPC không bị chuyển đến NAT Gateway. Việc NAT Gateway tồn tại không tự cập nhật route table của private subnet; route và subnet association cần được cấu hình riêng.

### So sánh NAT Gateway, NAT instance và VPC endpoint

| Lựa chọn | Phù hợp khi | Ưu điểm | Đánh đổi và giới hạn |
|---|---|---|---|
| NAT Gateway | Cần outbound IPv4 tổng quát, được quản lý, từ private subnet | AWS quản lý dịch vụ; không phải tự vá hệ điều hành hoặc quản lý Auto Scaling cho NAT host | Có phí theo thời gian và dữ liệu xử lý; phạm vi một AZ; không phải firewall outbound đầy đủ. |
| NAT instance | Lab đặc biệt hoặc workload có yêu cầu tùy biến mà tổ chức chấp nhận tự vận hành | Có thể tùy biến hệ điều hành, firewall và một số chức năng mạng | Phải quản lý instance, source/destination check, HA, patching, scaling và failover; thường không nên chọn chỉ để tiết kiệm mà bỏ qua chi phí vận hành. |
| VPC endpoint | Workload truy cập dịch vụ AWS hoặc SaaS được hỗ trợ qua PrivateLink | Tránh gửi một số traffic AWS qua NAT/Internet; có thể giảm phạm vi egress công khai | Chỉ dùng được cho service và kiểu endpoint được hỗ trợ; có cấu hình, policy và chi phí riêng. |
| Egress-only Internet Gateway | Workload IPv6 cần outbound-only ra Internet | Hỗ trợ định tuyến IPv6 outbound và chặn kết nối IPv6 inbound khởi tạo từ Internet | Chỉ dành cho IPv6; không thay thế NAT Gateway IPv4. |

### NAT Gateway không phải firewall

NAT Gateway cung cấp chuyển đổi địa chỉ và state cho kết nối; nó không phải proxy nhận biết ứng dụng hay firewall egress có policy theo domain. Nếu một workload bị xâm nhập, NAT không tự ngăn workload mở kết nối outbound đến một endpoint độc hại. Khi cần giới hạn đích theo domain, giao thức hoặc nội dung, cần xem xét proxy, AWS Network Firewall, DNS controls, service-specific policy, logging và các lớp bảo vệ phù hợp khác.

## 3. Cách hoạt động: outbound IPv4 từ private subnet

```text
Workload trong private subnet
  │ private IPv4, khởi tạo kết nối outbound
  ▼
Route table của private subnet
  │ 0.0.0.0/0 → public NAT Gateway
  ▼
NAT Gateway trong public subnet
  │ thay source private IPv4 bằng EIP
  ▼
Route table public subnet
  │ 0.0.0.0/0 → Internet Gateway
  ▼
Internet hoặc endpoint bên ngoài
  │ response thuộc kết nối đã khởi tạo
  ▼
IGW → NAT Gateway → workload ban đầu
```

Các bước chi tiết:

1. **Workload khởi tạo kết nối.** Một instance hoặc task trong private subnet gửi packet IPv4 đến đích bên ngoài VPC. Workload dùng private IPv4 address; nó không cần public IPv4 chỉ để khởi tạo kết nối qua NAT.
2. **Route table của private subnet chọn NAT Gateway.** Route `0.0.0.0/0` trỏ đến NAT Gateway được chọn cho các IPv4 destination không có route cụ thể hơn. Traffic nội bộ VPC vẫn khớp route `local`.
3. **NAT Gateway chuyển tiếp traffic.** NAT Gateway ghi nhận trạng thái kết nối và thay địa chỉ nguồn private bằng EIP của public NAT Gateway. Bên ngoài nhìn thấy địa chỉ public của gateway, không thấy private IPv4 của workload trong packet đã NAT.
4. **Public subnet đưa traffic ra Internet.** Route table của subnet đặt NAT Gateway cần có `0.0.0.0/0` trỏ đến IGW. IGW phải gắn với đúng VPC. Nếu thiếu bất kỳ phần nào trong chuỗi này, đường outbound sẽ không hoạt động.
5. **Response quay lại qua trạng thái NAT.** Response thuộc kết nối đã được tạo từ bên trong được gửi về EIP, qua IGW đến NAT Gateway. Gateway dùng trạng thái kết nối để chuyển response về private IPv4 của workload.
6. **Kết nối mới từ Internet không được tự động mở vào private workload.** NAT không tạo port forwarding tổng quát cho kết nối khởi tạo từ Internet. Tuy nhiên, bảo vệ vẫn cần security group, network ACL và ứng dụng cấu hình đúng; NAT không thay thế những lớp này.

Security group là stateful nên traffic phản hồi của kết nối được cho phép thường được nhận diện theo trạng thái kết nối. Network ACL là stateless nên phải cho phép cả chiều đi và chiều về, bao gồm các ephemeral ports cần thiết cho luồng cụ thể. Route đúng nhưng firewall chặn vẫn làm kết nối thất bại; firewall mở nhưng route sai cũng không tạo được đường đi.

## 4. Tư duy kiến trúc, bảo mật, chi phí và đánh đổi

### Tính sẵn sàng và khả năng phục hồi

NAT Gateway do AWS quản lý và có khả năng phục hồi trong phạm vi AZ nơi nó được triển khai, nhưng mỗi NAT Gateway được gắn với một AZ. Khi một private subnet ở AZ khác gửi traffic qua NAT Gateway đó, traffic đi cross-AZ. Điều này tạo phụ thuộc vào AZ chứa NAT Gateway và có thể phát sinh thêm data transfer cross-AZ theo bảng giá hiện hành.

Có hai mẫu thiết kế phổ biến:

| Thiết kế | Cách định tuyến | Ưu điểm | Nhược điểm |
|---|---|---|---|
| Một NAT Gateway dùng chung | Các private subnet ở nhiều AZ cùng trỏ đến một NAT Gateway | Ít gateway hơn, phù hợp bài lab/dev khi chấp nhận đánh đổi | Nếu AZ của gateway gặp sự cố, outbound của tất cả subnet phụ thuộc gateway có thể bị ảnh hưởng; traffic từ AZ khác đi cross-AZ và có thể tốn phí. |
| Một NAT Gateway cho mỗi AZ | Mỗi private subnet/AZ trỏ đến NAT Gateway nằm cùng AZ | Tránh phụ thuộc outbound vào một AZ duy nhất và giảm luồng cross-AZ qua NAT | Phí theo giờ và theo dữ liệu cao hơn vì có nhiều gateway; cần route table theo AZ được quản lý rõ ràng. |

Trong môi trường production, thường cân nhắc một NAT Gateway cho mỗi AZ có private workload để tránh phụ thuộc cross-AZ và cải thiện khả năng phục hồi. Đây không phải quy tắc bất biến: quyết định phải dựa trên yêu cầu availability, lưu lượng, chi phí, SLA và phương án egress thay thế. Không giả định một NAT Gateway duy nhất cung cấp tính sẵn sàng đa AZ chỉ vì dịch vụ là managed.

NAT Gateway không phải cơ chế phục hồi dữ liệu và không thay thế multi-AZ cho ứng dụng hay database. Khi đánh giá lỗi AZ, cần kiểm tra cả route table, workload placement, DNS, health check và khả năng chuyển workload; không giả lập sự cố bằng cách xóa NAT Gateway khỏi lab dùng chung.

### Bảo mật

- Giữ compute và database không có public IPv4 nếu chúng không cần endpoint public. Chỉ NAT Gateway được đặt trong public subnet cho luồng egress IPv4 này.
- Hạn chế security group outbound theo workload khi có thể; không mặc định rằng qua NAT đồng nghĩa traffic an toàn.
- Kiểm soát inbound ở security group và network ACL riêng. Không mở inbound từ Internet vào NAT Gateway với kỳ vọng cho phép truy cập workload private.
- Dùng TLS để bảo vệ dữ liệu trên đường truyền. NAT không mã hóa payload.
- Dùng VPC endpoint và endpoint policy cho dịch vụ AWS khi phù hợp; kết hợp IAM least privilege để workload chỉ truy cập đúng tài nguyên.
- Cân nhắc logging/monitoring phù hợp cho yêu cầu điều tra và kiểm soát egress. NAT Gateway không cung cấp policy lọc theo domain như một proxy.
- Không đưa EIP, subnet ID hoặc cấu hình mạng nội bộ có tính nhạy cảm vào nơi công khai nếu chính sách tổ chức không cho phép. Không lưu credentials trong Terraform variables, `terraform.tfvars` hoặc state dưới dạng không được bảo vệ.

### Chi phí

NAT Gateway có thể phát sinh phí đáng kể ngay cả khi bài lab không chạy nhiều compute. Các yếu tố thường cần tính gồm:

- Phí theo thời gian NAT Gateway tồn tại, phụ thuộc Region.
- Phí theo mỗi GB được NAT Gateway xử lý.
- Data transfer ra Internet hoặc giữa AZ, tùy đường đi và bảng giá hiện hành.
- Public IPv4/EIP và các khoản liên quan theo chính sách giá tại thời điểm triển khai.
- Chi phí của EC2, ECS, database, logging hoặc endpoint được dùng để kiểm thử đường đi.

Một NAT Gateway dùng chung có thể giảm số gateway nhưng không xóa phí theo thời gian, phí xử lý dữ liệu hoặc rủi ro cross-AZ. Mỗi AZ có NAT Gateway riêng cải thiện tính độc lập AZ nhưng tăng số tài nguyên tính phí. Kiểm tra bảng giá của đúng Region và AWS Pricing Calculator trước khi apply; không dựa vào free tier hay khoản credit để mặc định rằng NAT Gateway miễn phí.

Trong bài thực hành, chỉ cần kiểm tra plan và cấu hình routing nếu chưa được xác nhận ngân sách/chi phí. Nếu triển khai thật để kiểm tra, đặt thời gian sử dụng ngắn, theo dõi chi phí và dọn tài nguyên tạm theo đúng state; lab dùng chung chỉ được destroy khi đã xác nhận không còn cần cho các section sau.

### Lựa chọn kiến trúc và đánh đổi

- **Dùng NAT Gateway cho outbound Internet tổng quát:** Phù hợp khi workload private cần truy cập nhiều endpoint IPv4 ngoài VPC và không có endpoint riêng phù hợp. Đổi lại phải chấp nhận phí, thiết kế AZ và kiểm soát egress.
- **Dùng VPC endpoint cho dịch vụ AWS:** Phù hợp khi đích là service được hỗ trợ và cần private connectivity. Endpoint có thể tránh NAT cho traffic tương ứng, nhưng cần quản lý endpoint policy, DNS, route/security group theo loại endpoint và chi phí riêng.
- **Dùng NAT Gateway đơn lẻ trong dev:** Có thể giảm số gateway cho một lab ngắn, nhưng phải ghi rõ đây là đánh đổi chi phí lấy khả năng chịu lỗi thấp hơn và có thể có cross-AZ. Không sao chép cấu hình này sang prod mà không đánh giá.
- **Dùng NAT Gateway mỗi AZ trong prod:** Thường giảm phụ thuộc vào một AZ và tránh cross-AZ cho đường NAT. Cần xác nhận traffic và giá để cân đối thêm chi phí cố định.
- **Dùng NAT instance:** Chỉ chọn khi có yêu cầu tùy biến hoặc lý do chi phí đã được đo lường, và có kế hoạch vận hành HA, patching, scaling và failover. Không coi NAT instance là thay thế tương đương không cần vận hành.
- **Dùng egress-only Internet Gateway cho IPv6:** Phù hợp với IPv6 outbound-only. Nếu workload dùng dual-stack, cần thiết kế route IPv4 và IPv6 riêng; NAT Gateway không nhận trách nhiệm NAT IPv6.

### IPv6 và giới hạn của NAT Gateway

NAT Gateway trong mô hình bài học này xử lý NAT cho IPv4. Với IPv6, một workload có thể dùng địa chỉ IPv6 toàn cục; để cho phép khởi tạo kết nối outbound nhưng chặn kết nối khởi tạo inbound từ Internet, VPC có thể dùng egress-only Internet Gateway và route IPv6 `::/0` tương ứng. Nếu cần IPv6 inbound, thiết kế định tuyến và kiểm soát khác sẽ được áp dụng; không nên suy ra hành vi IPv6 chỉ từ route IPv4 `0.0.0.0/0`.

## 5. Quan sát trên AWS Management Console

Mục tiêu phần này là đọc topology hiện có, không tạo NAT Gateway trên Console. Không tạo resource bằng Console nếu Terraform sẽ quản lý cùng resource.

1. **Xác nhận account và Region.** Trong AWS Management Console, xác nhận account được phép dùng và Region của VPC. NAT Gateway và route table là tài nguyên có phạm vi Region/AZ; xem nhầm Region có thể dẫn đến hiểu sai topology.
2. **Mở VPC.** Tìm dịch vụ **VPC** bằng thanh tìm kiếm, mở **Your VPCs** và chọn VPC của lab. Ghi nhận VPC ID, CIDR IPv4 và trạng thái.
3. **Đọc subnet theo AZ.** Mở **Subnets**, lọc theo VPC và xác định public/private subnet bằng route table thực tế, không chỉ dựa vào tên. Ghi lại subnet ID, AZ, CIDR và trạng thái auto-assign public IPv4.
4. **Đọc NAT Gateways.** Mở **NAT Gateways** và kiểm tra trạng thái, loại connectivity, subnet, AZ, EIP và VPC nếu có NAT Gateway. Nếu không có NAT Gateway, ghi nhận đó là trạng thái hiện tại; không tạo mới trong bước quan sát.
5. **Đọc route table.** Mở **Route tables** và xem tab **Routes** cùng **Subnet associations**. Public subnet cần route IPv4 mặc định đến IGW; private subnet dùng public NAT cần route IPv4 mặc định đến NAT Gateway. Kiểm tra route `local` vẫn hiện diện.
6. **Liên hệ với sơ đồ.** Lần theo một route outbound từ private subnet qua NAT Gateway, route table public subnet rồi đến IGW. Xác định AZ nào chứa gateway và private subnet nào đang phụ thuộc vào nó.
7. **Kiểm tra giới hạn chi phí.** Xem CloudWatch metrics hoặc Cost Explorer nếu có quyền để hiểu gateway có đang xử lý traffic hay không. Chỉ đọc; không chỉnh route, xóa gateway hoặc sửa allocation.

Nếu account không có VPC/NAT để quan sát, dùng sơ đồ trong bài và đọc topology của lab Terraform; không cần cấp quyền quản trị hoặc tạo tài nguyên chỉ để hoàn thành phần Console.

## 6. Thực hành

> - **Mục tiêu:** Mở rộng networking module dùng chung để minh họa private subnet IPv4 đi outbound qua public NAT Gateway, hiểu rõ route và kiểm tra cấu hình bằng Terraform plan.
> - **Môi trường:** Chỉ sử dụng `dev/lab/` của lab xuyên suốt Sections 1–5. Không tạo root module/state riêng cho bài 4. Không triển khai prod trong bài này.
> - **Chi phí dự kiến:** Có thể phát sinh phí theo giờ và dữ liệu xử lý của NAT Gateway, phí public IPv4/EIP, data transfer và tài nguyên kiểm thử. Phải kiểm tra giá hiện hành theo Region trước khi apply.
> - **Rủi ro và phạm vi:** Thay đổi networking module dùng chung ảnh hưởng các bài sau. Không tạo hoặc thay đổi tài nguyên bằng Console, không xóa VPC/IGW/public subnet hiện có và không chạy `terraform destroy` để dọn riêng bài này. Nếu chưa được xác nhận về chi phí, chỉ chạy validate/plan, không apply.

### Kiến trúc lab

Bài tập mở rộng VPC và public subnet đã hình thành ở bài trước; thêm private subnet ở hai AZ, một public NAT Gateway để minh họa đường outbound IPv4 dùng chung, một private route table và association đến các private subnet.

```text
                       Internet
                          ▲
                          │
                    Internet Gateway
                          ▲
              public route: 0.0.0.0/0
                          ▲
            NAT Gateway + Elastic IP
             đặt trong public subnet AZ-a
               ▲                      ▲
               │                      │
 private subnet AZ-a        private subnet AZ-b
   default → NAT               default → NAT
```

Đây là cấu hình dev tối giản để học luồng route; subnet ở AZ-b đi cross-AZ đến NAT Gateway ở AZ-a. Cấu hình này không phải khuyến nghị production đa AZ. Production thường cần đánh giá NAT Gateway theo từng AZ, endpoint, lưu lượng, SLA và chi phí.

### Điều kiện trước khi bắt đầu

- Networking module trong `dev/lab/` đã có VPC, public subnet ở ít nhất hai AZ, IGW, public route table, IPv4 default route đến IGW và public subnet associations.
- Tất cả các resource của VPC hiện có được quản lý bởi đúng Terraform state của `dev/lab/`. Không tạo resource trùng trong state khác.
- Đã xác nhận AWS account, Region, backend/state và quyền IAM cần thiết. Quyền `plan`/đọc và quyền `apply` không nhất thiết giống nhau.
- Terraform đã cài theo phiên bản dự án. Chạy lệnh từ `dev/lab/`, không từ thư mục module.
- CIDR của private subnet đã được quy hoạch: chúng nằm trong CIDR VPC, không overlap với public subnet, subnet khác, VPN/on-premises hoặc mạng VPC kết nối.
- Có `terraform.tfvars` cục bộ nếu root module yêu cầu; chỉ chứa cấu hình không nhạy cảm và không được commit. Không đưa access key, credentials hoặc secrets vào biến.
- Đã đọc phần chi phí và có xác nhận trước khi tạo NAT Gateway có phí. Nếu chưa xác nhận, giới hạn thực hành ở cấu hình và `terraform plan`.

### Các bước thực hiện

1. **Kiểm tra cấu hình và state hiện có.** Từ thư mục dự án, mở `dev/lab/` và `dev/lab/modules/networking/`. Đọc `main.tf`, `variables.tf`, `outputs.tf`, provider/backend và module call hiện tại. Xác nhận resource addresses trong module khớp với kiến trúc trước bài này. Không giả định module rỗng hay state trống nếu VPC đã được triển khai từ trước.

2. **Quy hoạch CIDR private subnet.** Chọn hai CIDR không chồng lấn nằm trong VPC, mỗi subnet gắn với một AZ khác nhau. Ví dụ dưới đây chỉ mang tính minh họa và phải thay bằng CIDR đã được xác nhận:

   ```hcl
   private_subnet_cidrs = ["10.20.20.0/24", "10.20.21.0/24"]
   ```

   CIDR phải phù hợp quy hoạch mạng của dự án; ví dụ không chứng minh các dải này chưa được dùng ở nơi khác. AWS giữ lại một số địa chỉ trong mỗi subnet, vì vậy cần dự trữ đủ không gian cho workload và scale.

3. **Khai báo biến ở root và module.** Trong `dev/lab/variables.tf`, khai báo input root `private_subnet_cidrs` theo convention đã có. Trong `dev/lab/modules/networking/variables.tf`, thêm biến module cùng kiểu `list(string)` và validation cho CIDR hợp lệ, đúng số lượng subnet nếu bài chọn hai AZ. Truyền biến qua `module "networking"` hiện có trong root `main.tf`; không khai báo trùng module block.

   Nếu root module dùng `terraform.tfvars.example`, thêm giá trị cấu hình mẫu không nhạy cảm ở đó. Không ghi EIP, secret hoặc credentials làm input cố định; NAT Gateway và EIP nên được Terraform tạo/quản lý.

4. **Tạo private subnet trong module networking.** Dùng cùng nguồn AZ và quy ước key đang dùng cho public subnet. Với module ở bài trước sử dụng `data.aws_availability_zones.available` và key chuỗi `"0"`, `"1"`, phần minh họa có thể theo dạng:

   ```hcl
   locals {
     private_subnets = {
       for index, cidr in var.private_subnet_cidrs :
       tostring(index) => {
         cidr = cidr
         az   = data.aws_availability_zones.available.names[index]
       }
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

   Đây là đoạn mở rộng cho module đang sở hữu VPC. Nếu resource names hoặc module boundary hiện có khác, điều chỉnh tham chiếu theo code thực tế. Không tạo thêm `aws_vpc.this` nếu VPC đã do module/state này quản lý. Nếu VPC do module khác quản lý, dùng output VPC ID đã có thay vì tạo VPC thứ hai.

5. **Tạo một public NAT Gateway cho cấu hình học tập dev.** NAT Gateway cần đặt trong public subnet; chọn subnet ở AZ-a, trong ví dụ này là `aws_subnet.public["0"]`. Tạo EIP và NAT Gateway trong cùng networking module:

   ```hcl
   resource "aws_eip" "nat" {
     domain = "vpc"

     tags = {
       Name        = "${var.environment_name}-nat-eip"
       Environment = var.environment_name
     }
   }

   resource "aws_nat_gateway" "this" {
     allocation_id = aws_eip.nat.id
     subnet_id     = aws_subnet.public["0"].id

     depends_on = [
       aws_route.public_ipv4_default
     ]

     tags = {
       Name        = "${var.environment_name}-nat"
       Environment = var.environment_name
     }
   }
   ```

   `depends_on` đảm bảo route public đến IGW được tạo trước NAT Gateway để subnet được dùng làm public path đúng theo thiết kế. Kiểm tra resource name/key thực tế trước khi dùng. Nếu public subnet được cung cấp từ module khác, dùng output subnet ID và dependency phù hợp; không quản lý cùng NAT/EIP từ hai state.

6. **Tạo private route table và subnet associations.** Private subnet phải có route `local` mặc định của VPC và route IPv4 default đến NAT Gateway. Liên kết cả private subnet vào private route table:

   ```hcl
   resource "aws_route_table" "private" {
     vpc_id = aws_vpc.this.id

     tags = {
       Name        = "${var.environment_name}-private-rt"
       Environment = var.environment_name
     }
   }

   resource "aws_route" "private_ipv4_default" {
     route_table_id         = aws_route_table.private.id
     destination_cidr_block = "0.0.0.0/0"
     nat_gateway_id         = aws_nat_gateway.this.id
   }

   resource "aws_route_table_association" "private" {
     for_each = aws_subnet.private

     subnet_id      = each.value.id
     route_table_id = aws_route_table.private.id
   }
   ```

   Route đến NAT chỉ ảnh hưởng traffic IPv4 khớp `0.0.0.0/0`; route `local` tiếp tục xử lý traffic nội bộ VPC. Không đưa route `::/0` vào NAT Gateway. Nếu lab đã có private route table, hãy sửa cấu hình hiện có đúng ownership thay vì tạo association trùng.

7. **Cập nhật outputs của module.** Trong `modules/networking/outputs.tf`, chỉ xuất các giá trị cần thiết cho root/module dùng sau, chẳng hạn map private subnet IDs, private route table ID và NAT Gateway ID. Không xuất credentials hoặc secret. Giữ outputs hiện có để module khác và bài sau tiếp tục hoạt động.

8. **Format, init và validate.** Từ `dev/lab/`, chạy:

   ```powershell
   terraform fmt -recursive
   terraform init
   terraform validate
   ```

   `terraform init` sử dụng backend/provider đã cấu hình; không đổi backend hoặc di chuyển state trong bài này. `terraform validate` kiểm tra cú pháp và cấu trúc, nhưng không chứng minh CIDR không xung đột với mạng ngoài AWS, không chứng minh chi phí chấp nhận được và không xác minh data-plane traffic.

9. **Đọc plan trước khi apply.** Chạy `terraform plan` và kiểm tra:

   - Đang ở đúng account, Region, root module, backend và state của `dev/lab/`.
   - Plan chỉ thêm private subnet, EIP, NAT Gateway, private route table, routes, associations và outputs dự kiến.
   - Không có VPC, IGW, public subnet hoặc resource dùng chung bị xóa, thay thế hoặc tạo trùng.
   - NAT Gateway được đặt ở public subnet; private route table trỏ đúng NAT Gateway; public route table vẫn trỏ IGW.
   - CIDR không overlap, tags nhất quán, NAT không được tạo trong prod.
   - Người học đã xem bảng giá/ước tính chi phí cho khoảng thời gian gateway sẽ tồn tại.

   Nếu plan có bất kỳ deletion/replacement nào không được dự kiến, dừng lại để hiểu nguyên nhân. Không dùng `-target` hoặc xóa state để che khuất sai lệch.

10. **Chỉ apply khi được xác nhận.** NAT Gateway tạo phí theo thời gian và dữ liệu. Chỉ chạy `terraform apply` sau khi người học/chủ sở hữu xác nhận account, Region, state, resource scope và ngân sách. Nếu chưa có xác nhận, dừng ở plan; việc học cách đọc route không đòi hỏi phải tạo gateway thật.

### Xác minh kết quả

Nếu chỉ chạy plan, xác minh plan thể hiện đúng dependency và route; không kết luận rằng data-plane traffic đã hoạt động.

Nếu NAT Gateway đã được apply:

- Trên VPC Console, xác nhận NAT Gateway ở trạng thái `Available`, thuộc đúng VPC, nằm trong public subnet và sử dụng EIP dự kiến.
- Xác nhận route table public có `0.0.0.0/0` đến IGW và các public subnet được associate đúng.
- Xác nhận route table private có `0.0.0.0/0` đến NAT Gateway và tất cả private subnet mong muốn được associate.
- Xác nhận private subnet không có public IPv4 auto-assignment ngoài dự kiến; route table của private subnet không có default route trực tiếp đến IGW.
- Xác nhận route `local` vẫn tồn tại và các route/service endpoint khác không bị ghi đè.
- Với kiểm thử data-plane, dùng workload thử nghiệm đã được phê duyệt trong private subnet và giới hạn thời gian chạy. Một request outbound thành công chứng minh đường đi cụ thể hoạt động; nó không chứng minh mọi outbound đều an toàn hay private workload không thể bị truy cập qua các đường khác.
- Theo dõi CloudWatch metrics của NAT Gateway và chi phí thực tế khi có traffic. Đặt ngưỡng/cảnh báo nếu phù hợp.

Không tạo EC2/ECS task thử nghiệm tự phát: compute, public IPv4 và data transfer có thể tạo phí riêng. Nếu chưa có workload thử nghiệm được quản lý bởi lab, dừng ở xác minh cấu hình route.

### Xử lý lỗi thường gặp

| Triệu chứng | Nguyên nhân có thể có | Cách kiểm tra và khắc phục |
|---|---|---|
| NAT Gateway không chuyển sang `Available` | Cấu hình subnet/EIP, quota, account/Region hoặc lỗi tạo resource | Đọc trạng thái/message trên Console và Terraform error; kiểm tra quota và đúng VPC/subnet. Không xóa state thủ công. |
| Workload private không ra Internet | Thiếu/sai route private, NAT chưa `Available`, public subnet thiếu IGW route, network ACL chặn chiều về hoặc security group outbound không cho phép | Lần theo route table và subnet association từng chặng; kiểm tra cả firewall hai chiều cần thiết và trạng thái gateway. |
| Private workload dùng public address ngoài ý muốn | Auto-assign public IPv4 được bật hoặc resource được cấp public IP riêng | Kiểm tra subnet setting và cấu hình resource; tắt auto-assign cho private subnet và loại bỏ public addressing theo plan đã review. |
| Kết nối đến AWS service vẫn qua NAT | Thiếu endpoint phù hợp, DNS/route/policy endpoint sai hoặc endpoint chưa được liên kết | Xác định service đích và kiểu endpoint; kiểm tra endpoint policy, DNS và route/security group tùy endpoint type. |
| Kết nối IPv6 không hoạt động qua NAT Gateway | NAT Gateway không xử lý route IPv6 `::/0` | Thiết kế route IPv6 riêng; với outbound-only IPv6, đánh giá egress-only Internet Gateway. |
| NAT Gateway hoạt động nhưng chi phí cao | Gateway tồn tại lâu, nhiều dữ liệu qua NAT, cross-AZ hoặc traffic AWS có thể dùng endpoint riêng | Kiểm tra Cost Explorer/metrics/flow logs phù hợp; đánh giá VPC endpoint, số gateway, lượng traffic và cleanup đã được phê duyệt. |
| `terraform plan` báo replacement hoặc resource trùng | Đổi key/resource address, đã có resource ngoài state hoặc ownership bị chia giữa nhiều state | So sánh Terraform state, code và Console; lập kế hoạch migration/import đúng chuẩn nếu cần. Không apply khi chưa rõ tác động. |

### Dọn dẹp tài nguyên

NAT Gateway, EIP và các private subnet/route table được thêm cho lab có thể thuộc cấu hình networking dùng chung. Không xóa chúng chỉ vì kết thúc bài 4; các bài sau có thể cần private subnet. Không chạy `terraform destroy` từ `dev/lab/`.

Nếu lab cuối cùng được chủ sở hữu xác nhận là không còn cần:

1. Xác nhận đây đúng là dev/lab, đúng account, Region, backend và state; inventory rõ resource nào được tạo bởi lab.
2. Xác nhận không có bài hoặc workload đang dùng private subnet, NAT, route table hay EIP.
3. Xem destroy plan đầy đủ; dừng nếu plan ảnh hưởng VPC, IGW, resource dùng chung hoặc dữ liệu khác ngoài phạm vi.
4. Chỉ apply destroy sau khi nhận được xác nhận rõ cho toàn bộ phạm vi cleanup.
5. Xác minh gateway/EIP/resource đã được xóa và theo dõi Cost Explorer vì dữ liệu chi phí có thể cập nhật trễ.

Không dùng hướng dẫn cleanup này cho `prod/lab/`, `dev/capstone/` hoặc `prod/capstone/`. Production cần quy trình thay đổi, availability, phê duyệt và rollback riêng.

## 7. Bài tập tự kiểm tra

1. Một private subnet có route `0.0.0.0/0 → NAT Gateway`, nhưng NAT Gateway nằm trong subnet không có route `0.0.0.0/0 → IGW`. Workload có thể truy cập Internet không? Hãy giải thích toàn bộ đường đi và chỉ ra điểm thiếu.
2. Hai private subnet ở hai AZ cùng dùng một NAT Gateway trong AZ-a. Mô tả lợi ích chi phí và hai rủi ro kiến trúc cần cân nhắc so với mỗi AZ có một NAT Gateway.
3. Workload chỉ cần tải object từ Amazon S3 và gọi một API public bên ngoài. So sánh NAT Gateway, S3 VPC endpoint và kiến trúc kết hợp; nêu các câu hỏi cần trả lời trước khi chọn.
4. Một máy chủ Internet không thể mở kết nối mới đến EC2 trong private subnet, nhưng EC2 có thể tải bản cập nhật outbound qua NAT Gateway. Vì sao hai kết quả này không mâu thuẫn?
5. Vì sao không thể dùng NAT Gateway IPv4 để cung cấp outbound-only cho workload IPv6? Thành phần định tuyến nào cần được đánh giá cho IPv6?

### Gợi ý đáp án

1. Không. Route ở private subnet mới chỉ gửi traffic đến NAT Gateway. Public NAT Gateway cần được đặt trong public subnet và public subnet đó cần route mặc định đến IGW; IGW phải gắn với VPC. Thiếu chặng ra Internet thì đường đi chưa hoàn chỉnh.
2. Một NAT Gateway giảm số gateway và có thể giảm phí theo giờ so với một gateway ở mỗi AZ. Đổi lại, private subnet ở AZ-b gửi cross-AZ đến NAT tại AZ-a, có thể phát sinh phí data transfer; đồng thời outbound của cả hai AZ phụ thuộc vào AZ-a. Thiết kế một gateway/AZ tăng chi phí gateway nhưng giảm các phụ thuộc đó.
3. NAT Gateway hỗ trợ outbound tổng quát đến API public nhưng có phí theo giờ và dữ liệu. S3 Gateway Endpoint có thể tạo đường riêng đến S3 mà không đưa traffic S3 qua NAT; endpoint policy và route association cần đúng. Kết hợp hai cách có thể dùng endpoint cho S3 và NAT cho API Internet còn lại. Cần xác minh Region, kiểu endpoint, DNS, policy, lượng traffic và giá thực tế.
4. NAT cho phép response quay lại đối với connection mà workload private khởi tạo và gateway ghi nhận trạng thái. Nó không mở port forwarding tổng quát để một bên Internet tùy ý khởi tạo connection mới vào workload. Security group, network ACL và các đường truy cập khác vẫn phải được kiểm tra.
5. NAT Gateway trong thiết kế này xử lý IPv4 và không chuyển tiếp route IPv6 `::/0`. Với IPv6 outbound-only, đánh giá egress-only Internet Gateway và route IPv6; nếu dùng dual-stack, phải kiểm tra riêng cả route IPv4 lẫn IPv6.

## Tổng kết kiến thức và nguyên tắc áp dụng

NAT Gateway là một điểm chuyển tiếp có trạng thái cho outbound IPv4 từ private subnet. Muốn đường đi hoạt động, private route table phải trỏ đến NAT Gateway; NAT Gateway phải nằm trong public subnet có đường đến IGW; IGW phải gắn đúng VPC. Mỗi lớp chỉ giải quyết một phần của kết nối, vì vậy cần lần theo đầy đủ route, subnet association, địa chỉ, firewall và trạng thái resource khi chẩn đoán.

Một NAT Gateway không làm private workload trở thành an toàn tuyệt đối và không phải firewall egress. Hãy giữ workload không cần public endpoint trong private subnet, giới hạn IAM/security group, dùng TLS, áp dụng VPC endpoint khi hợp lý và bổ sung kiểm soát egress/monitoring theo yêu cầu. Với IPv6, thiết kế riêng bằng route IPv6 và egress-only Internet Gateway khi mục tiêu là outbound-only.

Quyết định số lượng NAT Gateway là đánh đổi giữa chi phí và khả năng phục hồi theo AZ. Một gateway dùng chung phù hợp cho bài lab/dev ngắn khi người học hiểu và chấp nhận cross-AZ/dependency; production cần đánh giá gateway theo từng AZ, endpoint, lưu lượng, yêu cầu SLA và ngân sách. Trước khi tạo resource, kiểm tra bảng giá theo Region và plan; trước khi dọn, xác nhận state và resource dùng chung.

Hãy tự thiết kế đường outbound cho một ứng dụng chạy trên ECS ở hai AZ nhưng chỉ cần gọi S3 và một API Internet: traffic nào nên đi qua VPC endpoint, traffic nào cần NAT, route và quyền nào phải kiểm tra, và bạn sẽ chọn một hay hai NAT Gateway theo yêu cầu availability/chi phí nào?