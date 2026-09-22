import SwiftUI

enum GameState {
    case ready
    case growing
    case rotating
    case walking
    case falling
    case scrolling
    case gameOver
}

struct StickmanView: View {
    var isWalking: Bool = false
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let date = timeline.date
            let legAngle = isWalking ? date.timeIntervalSince1970.truncatingRemainder(dividingBy: 0.4) * 900 : 0
            
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2
                
                // Head
                let headRadius: CGFloat = 6
                let headCenter = CGPoint(x: centerX, y: headRadius + 2)
                context.stroke(
                    Path(ellipseIn: CGRect(x: headCenter.x - headRadius, y: headCenter.y - headRadius, width: headRadius * 2, height: headRadius * 2)),
                    with: .color(.black),
                    lineWidth: 2.5
                )
                
                // Body line
                let neckY = headCenter.y + headRadius
                let bodyLength: CGFloat = 16
                let hipY = neckY + bodyLength
                var bodyPath = Path()
                bodyPath.move(to: CGPoint(x: centerX, y: neckY))
                bodyPath.addLine(to: CGPoint(x: centerX, y: hipY))
                context.stroke(bodyPath, with: .color(.black), lineWidth: 2.5)
                
                // Arms
                let armY = neckY + 4
                var armPath = Path()
                let armOffset = isWalking ? sin(legAngle * .pi / 180) * 6 : 0
                armPath.move(to: CGPoint(x: centerX - 8, y: armY + armOffset))
                armPath.addLine(to: CGPoint(x: centerX, y: armY))
                armPath.addLine(to: CGPoint(x: centerX + 8, y: armY - armOffset))
                context.stroke(armPath, with: .color(.black), lineWidth: 2)
                
                // Legs
                let legLength: CGFloat = 14
                let legOffset = isWalking ? sin(legAngle * .pi / 180) * 8 : 4
                var legPath = Path()
                // Left leg
                legPath.move(to: CGPoint(x: centerX, y: hipY))
                legPath.addLine(to: CGPoint(x: centerX - legOffset, y: hipY + legLength))
                // Right leg
                legPath.move(to: CGPoint(x: centerX, y: hipY))
                legPath.addLine(to: CGPoint(x: centerX + legOffset, y: hipY + legLength))
                context.stroke(legPath, with: .color(.black), lineWidth: 2.5)
            }
            .frame(width: 24, height: 44)
        }
    }
}

struct ContentView: View {
    // GUI Controls & Settings
    @State private var initialPlatformWidth: Double = 120.0
    @State private var volatility: Double = 0.5
    @State private var walkingSpeedIncrease: Double = 10.0
    @State private var showSettings: Bool = false
    
    // Game State
    @State private var gameState: GameState = .ready
    @State private var score: Int = 0
    @State private var highScore: Int = 0
    @State private var statusMessage: String? = nil
    @State private var currentWalkingSpeed: Double = 160.0
    
    // Previous platform & stick tracking for smooth camera transition
    @State private var previousPlatformX: Double = 0.0
    @State private var previousPlatformWidth: Double = 0.0
    @State private var previousStickLength: Double = 0.0
    @State private var previousStickAngle: Double = 0.0
    
    // Platforms (Absolute X positions and Widths)
    @State private var currentPlatformX: Double = 0.0
    @State private var currentPlatformWidth: Double = 120.0
    
    @State private var targetPlatformX: Double = 220.0
    @State private var targetPlatformWidth: Double = 80.0
    
    // Stick
    @State private var stickLength: Double = 0.0
    @State private var stickAngle: Double = 0.0 // 0 = vertical up, 90 = horizontal right
    @State private var trimmingBaseStickLength: Double = 0.0
    @State private var canTrimWalkingStick: Bool = false
    @State private var didTrimWalkingStick: Bool = false
    
    // Stickman Position
    @State private var stickmanX: Double = 0.0
    @State private var stickmanY: Double = 0.0
    @State private var isWalking: Bool = false
    
    // Camera scroll offset
    @State private var cameraOffsetX: Double = 0.0
    
    // Timers
    @State private var growTimer: Timer? = nil
    @State private var rescueWalkTimer: Timer? = nil
    
    // Screen width tracking
    @State private var screenWidth: CGFloat = 400.0
    
    // Fixed platform height
    private let platformHeight: CGFloat = 200
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background: Pure White
                Color.white.ignoresSafeArea()
                
                // Game World Canvas (offset by camera)
                ZStack(alignment: .bottomLeading) {
                    
                    // 0. Previous Platform & Stick (Rendered during scrolling so old stick stays on old platform)
                    if gameState == .scrolling {
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: max(0, previousPlatformWidth), height: platformHeight)
                            .position(
                                x: previousPlatformX + previousPlatformWidth / 2,
                                y: geometry.size.height - platformHeight / 2
                            )
                        
                        let prevStickBaseX = previousPlatformX + previousPlatformWidth
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 4, height: previousStickLength)
                            .rotationEffect(.degrees(previousStickAngle), anchor: .bottom)
                            .position(
                                x: prevStickBaseX - 2,
                                y: geometry.size.height - platformHeight - previousStickLength / 2
                            )
                    }
                    
                    // 1. Starting / Current Platform (Grey)
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: max(0, currentPlatformWidth), height: platformHeight)
                        .position(
                            x: currentPlatformX + currentPlatformWidth / 2,
                            y: geometry.size.height - platformHeight / 2
                        )
                    
                    // 2. Target Platform (Red)
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: max(0, targetPlatformWidth), height: platformHeight)
                        
                        // Perfect landing zones: wider zones give smaller bonuses, center zone gives the largest bonus.
                        Rectangle()
                            .fill(Color.yellow.opacity(0.35))
                            .frame(width: max(0, targetPlatformWidth * 0.50), height: 6)
                        Rectangle()
                            .fill(Color.yellow.opacity(0.65))
                            .frame(width: max(0, targetPlatformWidth * 0.25), height: 6)
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: max(0, targetPlatformWidth * 0.10), height: 6)
                    }
                    .position(
                        x: targetPlatformX + targetPlatformWidth / 2,
                        y: geometry.size.height - platformHeight / 2
                    )
                    
                    // 3. Wooden Stick (Black) - anchored at right edge of current platform
                    let stickBaseX = currentPlatformX + currentPlatformWidth
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 4, height: stickLength)
                        .rotationEffect(.degrees(stickAngle), anchor: .bottom)
                        .position(
                            x: stickBaseX - 2,
                            y: geometry.size.height - platformHeight - stickLength / 2
                        )
                    
                    // 4. Stickman (Player)
                    StickmanView(isWalking: isWalking)
                        .position(
                            x: stickmanX,
                            y: geometry.size.height - platformHeight - 22 + stickmanY
                        )
                }
                .offset(x: -cameraOffsetX)
                .frame(width: geometry.size.width, height: geometry.size.height)
                
                // Top HUD / GUI Controls Overlay
                VStack {
                    HStack(alignment: .top) {
                        // Score Display on Top Left
                        VStack(alignment: .leading, spacing: 4) {
                            Text("得分: \(score)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                            Text("最高分: \(highScore)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, 20)
                        
                        Spacer()
                        
                        // Right Controls Panel
                        VStack(alignment: .trailing, spacing: 10) {
                            HStack(spacing: 12) {
                                Button(action: {
                                    withAnimation {
                                        showSettings.toggle()
                                    }
                                }) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.black)
                                        .clipShape(Circle())
                                }
                                
                                Button(action: resetGame) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("重置遊戲")
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.black)
                                    .cornerRadius(20)
                                }
                            }
                            
                            // Expandable Settings Panel
                            if showSettings {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("遊戲參數設置")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.black)
                                    
                                    Divider()
                                    
                                    // 1. Length / Platform Width Control (長度)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("起始地面長度:")
                                                .font(.system(size: 13, weight: .medium))
                                            Spacer()
                                            Text("\(Int(initialPlatformWidth))")
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                        Slider(value: $initialPlatformWidth, in: 50...250, step: 10) { _ in
                                            if gameState == .ready || gameState == .gameOver {
                                                currentPlatformWidth = initialPlatformWidth
                                                stickmanX = currentPlatformX + currentPlatformWidth - 14
                                            }
                                        }
                                    }
                                    
                                    // 2. Volatility Control (動盪區間 0~1)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("動盪區間 (0~1):")
                                                .font(.system(size: 13, weight: .medium))
                                            Spacer()
                                            Text(String(format: "%.2f", volatility))
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                        Slider(value: $volatility, in: 0.0...1.0, step: 0.05)
                                    }
                                    
                                    // 3. Walking Speed Increase Control
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("速度遞增幅度:")
                                                .font(.system(size: 13, weight: .medium))
                                            Spacer()
                                            Text("+\(Int(walkingSpeedIncrease))")
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                        Slider(value: $walkingSpeedIncrease, in: 0...60, step: 5)
                                    }
                                    
                                    Text("公式: 起始地面 - 起始地面 × (0 ~ 動盪區間)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                .padding(14)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                                .frame(width: 240)
                            }
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 50)
                    
                    // Status / Feedback message
                    if let statusMessage = statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .transition(.scale.combined(with: .opacity))
                            .padding(.top, 20)
                    }
                    
                    Spacer()
                    
                    // Instruction Banner
                    if gameState == .ready || canTrimWalkingStick {
                        Text(canTrimWalkingStick ? "角色行走時點按螢幕剪短木板，每次 -2%" : "長按螢幕下半部伸長木板")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(.bottom, 60)
                    }
                }
                
                // Touch Overlay for lower half of the screen only
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: geometry.size.height / 2)
                    
                    Color.clear
                        .frame(height: geometry.size.height / 2)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if gameState == .ready {
                                        startGrowing()
                                    }
                                }
                                .onEnded { _ in
                                    if gameState == .growing {
                                        stopGrowingAndRotate()
                                    }
                                }
                        )
                }
                
                // Game Over Overlay
                if gameState == .gameOver {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            Text("遊戲結束")
                                .font(.system(size: 32, weight: .black))
                                .foregroundColor(.red)
                            
                            Text("最終得分: \(score)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                            
                            Button(action: resetGame) {
                                Text("再試一次")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 12)
                                    .background(Color.black)
                                    .cornerRadius(25)
                            }
                        }
                        .padding(30)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(radius: 10)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if gameState == .walking && canTrimWalkingStick {
                            trimWalkingStickByTap()
                        }
                    }
            )
            .onAppear {
                screenWidth = geometry.size.width
                setupInitialGame()
            }
            .onDisappear {
                growTimer?.invalidate()
                growTimer = nil
                rescueWalkTimer?.invalidate()
                rescueWalkTimer = nil
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                screenWidth = newWidth
            }
        }
    }
    
    // MARK: - Game Setup & Logic
    
    private func setupInitialGame() {
        score = 0
        cameraOffsetX = 0
        currentPlatformX = 0
        currentPlatformWidth = initialPlatformWidth
        previousPlatformX = 0
        previousPlatformWidth = 0
        previousStickLength = 0
        previousStickAngle = 0
        currentWalkingSpeed = 160.0
        trimmingBaseStickLength = 0
        canTrimWalkingStick = false
        didTrimWalkingStick = false
        
        // Spawn first target platform on screen
        targetPlatformWidth = generatePlatformWidth(from: currentPlatformWidth)
        let gap = Double.random(in: 60...140)
        targetPlatformX = currentPlatformX + currentPlatformWidth + gap
        
        resetStickAndMan()
        gameState = .ready
        statusMessage = nil
    }
    
    private func resetGame() {
        growTimer?.invalidate()
        growTimer = nil
        rescueWalkTimer?.invalidate()
        rescueWalkTimer = nil
        withAnimation {
            setupInitialGame()
        }
    }
    
    /// Target ground formula: 起始地面 - 起始地面 × (0 ~ 動盪區間)
    private func generatePlatformWidth(from baseWidth: Double) -> Double {
        let randFactor = Double.random(in: 0...volatility)
        let generatedWidth = baseWidth - (baseWidth * randFactor)
        return max(15.0, generatedWidth)
    }
    
    private func resetStickAndMan() {
        stickLength = 0
        stickAngle = 0
        trimmingBaseStickLength = 0
        canTrimWalkingStick = false
        stickmanX = currentPlatformX + currentPlatformWidth - 14
        stickmanY = 0
        isWalking = false
    }
    
    private func startGrowing() {
        gameState = .growing
        statusMessage = nil
        
        growTimer?.invalidate()
        let timer = Timer(timeInterval: 0.016, repeats: true) { _ in
            stickLength += 3.5
        }
        RunLoop.main.add(timer, forMode: .common)
        growTimer = timer
    }
    
    private func stopGrowingAndRotate() {
        growTimer?.invalidate()
        growTimer = nil
        gameState = .rotating
        
        withAnimation(.easeIn(duration: 0.4)) {
            stickAngle = 90
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            checkLanding()
        }
    }
    
    private func checkLanding() {
        let stickTipX = currentPlatformX + currentPlatformWidth + stickLength
        let targetMinX = targetPlatformX
        let targetMaxX = targetPlatformX + targetPlatformWidth
        
        if stickTipX < targetMinX {
            failLanding(destinationX: stickTipX)
        } else if stickTipX > targetMaxX {
            startStickTrimming()
        } else {
            completeSuccessfulLanding()
        }
    }
    
    private func completeSuccessfulLanding() {
        let stickTipX = currentPlatformX + currentPlatformWidth + stickLength
        let targetCenter = targetPlatformX + (targetPlatformWidth / 2)
        let landingDistanceFromCenter = abs(stickTipX - targetCenter)
        let landingRatio = landingDistanceFromCenter / targetPlatformWidth
        let scoreBonus: Int
        
        if didTrimWalkingStick {
            scoreBonus = 1
            statusMessage = "補救成功! +1"
        } else if landingRatio <= 0.05 {
            scoreBonus = 4
            statusMessage = "完美核心! +4"
        } else if landingRatio <= 0.125 {
            scoreBonus = 3
            statusMessage = "完美降落! +3"
        } else if landingRatio <= 0.25 {
            scoreBonus = 2
            statusMessage = "精準降落! +2"
        } else {
            scoreBonus = 1
            statusMessage = nil
        }
        
        score += scoreBonus
        if score > highScore {
            highScore = score
        }
        
        let destinationX = targetPlatformX + targetPlatformWidth - 14
        walkAcrossStick(destinationX: destinationX) {
            shiftWorldToNextPlatform()
        }
    }
    
    private func startStickTrimming() {
        trimmingBaseStickLength = stickLength
        canTrimWalkingStick = true
        gameState = .walking
        isWalking = true
        statusMessage = "行走中點按螢幕剪短木板"
        
        rescueWalkTimer?.invalidate()
        let timer = Timer(timeInterval: 0.016, repeats: true) { timer in
            let stickEndX = currentPlatformX + currentPlatformWidth + stickLength - 14
            let nextX = stickmanX + currentWalkingSpeed * 0.016
            
            if nextX >= stickEndX {
                stickmanX = stickEndX
                timer.invalidate()
                rescueWalkTimer = nil
                finishRescueWalk()
            } else {
                stickmanX = nextX
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rescueWalkTimer = timer
    }
    
    private func trimWalkingStickByTap() {
        guard canTrimWalkingStick else {
            return
        }
        
        let trimAmount = max(1.0, trimmingBaseStickLength * 0.02)
        let stickBaseX = currentPlatformX + currentPlatformWidth
        let minimumLengthUnderPlayer = max(0, stickmanX + 14 - stickBaseX)
        let newStickLength = max(minimumLengthUnderPlayer, stickLength - trimAmount)
        
        if newStickLength < stickLength {
            didTrimWalkingStick = true
            withAnimation(.easeOut(duration: 0.08)) {
                stickLength = newStickLength
            }
        }
    }
    
    private func finishRescueWalk() {
        guard canTrimWalkingStick else {
            return
        }
        
        canTrimWalkingStick = false
        isWalking = false
        evaluateFinalStickEnd()
    }
    
    private func evaluateFinalStickEnd() {
        let stickTipX = currentPlatformX + currentPlatformWidth + stickLength
        let targetMinX = targetPlatformX
        let targetMaxX = targetPlatformX + targetPlatformWidth
        
        if stickTipX >= targetMinX && stickTipX <= targetMaxX {
            completeSuccessfulLanding()
        } else {
            statusMessage = stickTipX < targetMinX ? "木板剪太短了" : "木板仍然太長"
            manFallDown()
        }
    }
    
    private func failLanding(destinationX: Double) {
        let targetMaxX = targetPlatformX + targetPlatformWidth
        let failDestination = min(destinationX, targetMaxX + 40)
        
        walkAcrossStick(destinationX: failDestination) {
            manFallDown()
        }
    }
    
    private func walkAcrossStick(destinationX: Double, completion: @escaping () -> Void) {
        gameState = .walking
        isWalking = true
        
        let distance = destinationX - stickmanX
        let walkDuration = max(0.2, distance / currentWalkingSpeed)
        
        withAnimation(.linear(duration: walkDuration)) {
            stickmanX = destinationX
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + walkDuration + 0.05) {
            isWalking = false
            completion()
        }
    }
    
    private func manFallDown() {
        gameState = .falling
        let stickTipX = currentPlatformX + currentPlatformWidth + stickLength
        
        withAnimation(.easeIn(duration: 0.5)) {
            stickmanY = 300
            if stickTipX < targetPlatformX {
                stickAngle = 180 // Stick falls down if too short
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            gameState = .gameOver
        }
    }
    
    private func shiftWorldToNextPlatform() {
        gameState = .scrolling
        
        // 1. 保存舊地面與舊木板資訊，讓舊木板在鏡頭移動時固定在舊地面上隨畫面推移移出
        previousPlatformX = currentPlatformX
        previousPlatformWidth = currentPlatformWidth
        previousStickLength = stickLength
        previousStickAngle = stickAngle
        
        // 2. 目標地面轉換為當前地面，並重置新木板為 0
        currentWalkingSpeed += walkingSpeedIncrease
        currentPlatformX = targetPlatformX
        currentPlatformWidth = targetPlatformWidth
        stickLength = 0
        stickAngle = 0
        trimmingBaseStickLength = 0
        canTrimWalkingStick = false
        didTrimWalkingStick = false
        
        // 3. 生成全新的目標地面，位置在當前鏡頭可視區域右方之外（畫面外）
        let nextWidth = generatePlatformWidth(from: currentPlatformWidth)
        targetPlatformWidth = nextWidth
        
        // 保證生成在畫面右邊界外至少 30pt
        let visibleRightEdge = cameraOffsetX + screenWidth
        let minNextX = max(currentPlatformX + currentPlatformWidth + 60.0, visibleRightEdge + 30.0)
        targetPlatformX = minNextX + Double.random(in: 0...50)
        
        // 4. 畫面鏡頭平滑滾動，將當前地面移動到螢幕最左邊 (cameraOffsetX 滾動到 currentPlatformX)
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraOffsetX = currentPlatformX
        }
        
        // 5. 滾動完成後進入就緒狀態
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            gameState = .ready
        }
    }
}

#Preview {
    ContentView()
}
