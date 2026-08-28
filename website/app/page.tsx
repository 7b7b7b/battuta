const downloadHref = '/downloads/Battuta-1.0.0-unnotarized.dmg';

const soundFamilies = [
  {
    name: '段落',
    description: '明确反馈，不必大声。',
    examples: 'Holy Panda · MX Brown · MX Clear · G915 Brown',
  },
  {
    name: '点击',
    description: '清脆、利落、颗粒分明。',
    examples: 'MX Blue · BOX Navy · BOX White · Blue Alps',
  },
  {
    name: '线性',
    description: '顺滑连续，适合长时间输入。',
    examples: 'Cream · Alpaca · Black Ink · Keychron Red',
  },
  {
    name: '经典结构',
    description: '不一样的触感记忆。',
    examples: 'Topre · IBM Buckling Spring',
  },
];

const installSteps = [
  {
    number: '01',
    title: '下载并拖入“应用程序”',
    body: '打开 DMG，把 Battuta 拖到其中的 Applications 快捷方式。不要直接从磁盘映像运行。',
  },
  {
    number: '02',
    title: '首次手动允许打开',
    body: '在“应用程序”里按住 Control 点按 Battuta，选择“打开”；如仍被拦截，请到“隐私与安全性”选择“仍要打开”。',
  },
  {
    number: '03',
    title: '开启“输入监控”',
    body: '从菜单栏 Battuta 面板请求授权，在系统设置中允许输入监控，然后退出并重新打开应用。',
  },
];

const faqItems = [
  {
    question: 'Battuta 会读取我输入的文字吗？',
    answer:
      '不会。Battuta 只用硬件键码、按下与抬起状态来选择声音，不读取字符内容，也不会保存或上传密码、输入文本或指针位置。',
  },
  {
    question: '为什么需要“输入监控”权限？',
    answer:
      'macOS 只有在用户明确允许后，才会把全局键盘事件交给 Battuta。这个权限让它能在浏览器、编辑器和聊天软件之间持续工作。',
  },
  {
    question: '声音会不会跟不上打字？',
    answer:
      '应用启动时会预热音频引擎，并把选中的样本预载为 48 kHz PCM。真正按键时只做内存查找和播放，不在输入路径上读取磁盘或转换格式。',
  },
  {
    question: '我可以制作自己的音色吗？',
    answer:
      '可以。DIY 编辑器支持通用按下与回弹音、键盘行、大键和逐键覆盖，也可以把完整的一次击键录音自动拆成按下与抬起两段。',
  },
];

export default function Home() {
  return (
    <main>
      <nav className="site-nav" aria-label="主导航">
        <a className="brand-lockup" href="#top" aria-label="Battuta 首页">
          <img src="/battuta-icon.png" alt="" />
          <span>Battuta</span>
        </a>
        <div className="nav-links">
          <a href="#sound">音效</a>
          <a href="#stats">统计</a>
          <a href="#privacy">隐私</a>
          <a href="#install">安装</a>
          <a className="nav-download" href={downloadHref} download>
            下载
          </a>
        </div>
      </nav>

      <header className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">Battuta for macOS</p>
          <h1>
            把喜欢的键盘声音，
            <span>装进你的 Mac。</span>
          </h1>
          <p className="hero-lede">
            一款常驻菜单栏的键盘与点击音效应用。从浏览器、编辑器到聊天软件，
            每一次输入都有清晰、自然的机械反馈。
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href={downloadHref} download>
              免费下载
            </a>
            <a className="button button-secondary" href="#sound">
              先听效果
            </a>
          </div>
          <p className="compatibility">
            macOS 13+ · Apple Silicon 与 Intel · Battuta 1.0.0
          </p>
        </div>

        <div className="hero-visual" aria-label="Battuta 应用图标">
          <div className="sound-ring sound-ring-one" />
          <div className="sound-ring sound-ring-two" />
          <img src="/battuta-icon.png" alt="Battuta 荧光绿机械键帽图标" />
        </div>

        <div className="hero-metrics" aria-label="Battuta 功能概览">
          <div><strong>20</strong><span>种键盘音色</span></div>
          <div><strong>5</strong><span>种点击风格</span></div>
          <div><strong>237</strong><span>段本地录音</span></div>
          <div className="metrics-note">本地处理 · 不记录输入内容</div>
        </div>
      </header>

      <section className="manifesto light-section">
        <div className="section-inner manifesto-grid">
          <p className="section-kicker">一把不存在于桌面的键盘</p>
          <div>
            <h2>
              你不需要换键盘，
              <span>也能换一种手感。</span>
            </h2>
            <p>
              Battuta 把真实的按下、回弹与大键录音，映射到你的每一次输入。
              写代码时来一点清脆反馈，长文写作用更柔和的声音，深夜则换成低调的静音风格。
            </p>
          </div>
        </div>
      </section>

      <section className="sound-section dark-section" id="sound">
        <div className="section-inner">
          <div className="section-heading section-heading-centered">
            <p className="section-kicker lime">真实输入，真实响应</p>
            <h2>按下有声音。抬起也有。</h2>
            <p>
              不只是循环播放一段录音。键盘行、空格、回车和退格会匹配不同样本；
              开启自然变化后，相同声音会在四种轻微配方之间均衡轮换，连续输入不再像“机关枪”。
            </p>
          </div>

          <div className="media-shell media-shell-dark">
            <div className="media-topbar">
              <span className="media-badge"><i />打开声音，听实际效果</span>
              <span>三组音色对比 · 约 24 秒</span>
            </div>
            <video
              controls
              playsInline
              preload="metadata"
              poster="/media/battuta-sound-poster.jpg"
              aria-label="Battuta 不同键盘音色的实际录屏演示"
            >
              <source src="/media/battuta-sound-demo-polished.mp4" type="video/mp4" />
              你的浏览器不支持视频播放。
            </video>
          </div>

          <div className="detail-grid three-columns">
            <article>
              <span className="detail-number">01</span>
              <h3>声音提前就绪</h3>
              <p>启动时预热音频引擎，切换音色时把样本预载到内存。真正打字时不临时读磁盘。</p>
            </article>
            <article>
              <span className="detail-number">02</span>
              <h3>自然，而非随机噪声</h3>
              <p>轻微的音量与速率变化采用均衡轮换，相邻两次不会重复同一配方。</p>
            </article>
            <article>
              <span className="detail-number">03</span>
              <h3>从键盘到触控板</h3>
              <p>键盘音量与点击音量分别控制，鼠标左右键、中键和触控板都能拥有自己的反馈。</p>
            </article>
          </div>
        </div>
      </section>

      <section className="palette-section">
        <div className="section-inner">
          <div className="split-heading">
            <div>
              <p className="section-kicker">20 种键盘音色</p>
              <h2>从轻薄到厚重，<br />总有一种适合今天。</h2>
            </div>
            <p>
              内置音色覆盖段落、点击、线性、静电容和屈曲弹簧等不同结构。
              不是只换一个滤镜，而是为不同键位准备对应的按下与回弹素材。
            </p>
          </div>

          <div className="sound-family-grid">
            {soundFamilies.map((family) => (
              <article key={family.name}>
                <span>{family.name}</span>
                <h3>{family.description}</h3>
                <p>{family.examples}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="stats-section light-section" id="stats">
        <div className="section-inner">
          <div className="section-heading section-heading-centered dark-copy">
            <p className="section-kicker green">不只听见，也能看见</p>
            <h2>你的打字习惯，留下一张地图。</h2>
            <p>
              查看今日输入量、峰值速度、常用应用、七日趋势、年度热力图与逐键分布。
              统计只保留聚合数量、物理键码、时间和前台应用，不保存你写下的内容。
            </p>
          </div>

          <div className="media-shell media-shell-light">
            <div className="media-topbar">
              <span className="media-badge dark"><i />本地输入统计</span>
              <span>静音循环展示</span>
            </div>
            <video
              autoPlay
              muted
              loop
              playsInline
              preload="metadata"
              poster="/media/battuta-stats-poster.jpg"
              aria-label="Battuta 本地输入统计功能录屏"
            >
              <source src="/media/battuta-stats-demo-polished-v2.mp4" type="video/mp4" />
              你的浏览器不支持视频播放。
            </video>
          </div>

          <div className="stats-feature-row">
            <article><strong>今天</strong><span>输入总量、峰值速度与最常使用的应用</span></article>
            <article><strong>历史</strong><span>七日趋势、年度热力图和活跃时段</span></article>
            <article><strong>键盘</strong><span>逐键热力图，看见真实的物理按键分布</span></article>
          </div>
        </div>
      </section>

      <section className="capabilities-section dark-section">
        <div className="section-inner">
          <div className="section-heading">
            <p className="section-kicker lime">让它真正属于你</p>
            <h2>不止选择。还可以自己制作。</h2>
          </div>

          <div className="bento-grid">
            <article className="bento-card bento-large bento-diy">
              <p className="card-label">DIY 音色编辑器</p>
              <h3>一段录音，自动拆成按下与抬起。</h3>
              <p>
                导入 WAV、AIFF、CAF、M4A 等常见音频；让 Battuta 自动建议切点，再用波形进行试听和微调。
                你可以覆盖整把键盘、某一排、大键，或某一个具体按键。
              </p>
              <a
                className="diy-editor-figure"
                href="/media/battuta-diy-editor.png"
                target="_blank"
                rel="noreferrer"
                aria-label="查看 Battuta DIY 音色编辑器完整截图"
              >
                <img
                  src="/media/battuta-diy-editor.png"
                  alt="Battuta DIY 音色编辑器，展示完整键盘映射、按下与回弹音频以及音色包检视器"
                  loading="lazy"
                  decoding="async"
                />
                <span>查看原图 ↗</span>
              </a>
            </article>

            <article className="bento-card bento-clicks">
              <p className="card-label">鼠标与触控板</p>
              <h3>5 种点击风格。</h3>
              <p>经典微动、静音微动、电竞脆响、厚重办公与玻璃触控板，键盘和点击音量互不影响。</p>
              <div className="click-pills" aria-hidden="true">
                <span>down</span><i /><span>up</span>
              </div>
            </article>

            <article className="bento-card bento-startup">
              <p className="card-label">日常使用</p>
              <h3>登录启动。后续一键更新。</h3>
              <p>安装完成后可以常驻菜单栏；从 1.0.0 升级到后续版本时，应用会校验更新包并自动替换重启。</p>
              <div className="status-line"><i />Battuta 正在运行</div>
            </article>
          </div>
        </div>
      </section>

      <section className="privacy-section" id="privacy">
        <div className="section-inner privacy-grid">
          <div>
            <p className="section-kicker">隐私不是开关，而是边界</p>
            <h2>它知道你按了键。<br />不知道你写了什么。</h2>
          </div>
          <div className="privacy-copy">
            <p>
              Battuta 只识别用于播放声音和生成聚合统计所需的硬件事件：物理键码、鼠标按钮、按下或抬起、时间以及前台应用。
            </p>
            <p>
              字符内容、密码、鼠标位置不会被读取、保存或上传。声音、DIY 音色包和输入统计都留在你的 Mac 上。
            </p>
            <div className="privacy-points">
              <span>不读取字符内容</span>
              <span>不上传输入统计</span>
              <span>MIT 开源可审查</span>
            </div>
          </div>
        </div>
      </section>

      <section className="install-section light-section" id="install">
        <div className="section-inner">
          <div className="section-heading section-heading-centered dark-copy">
            <p className="section-kicker green">开始使用</p>
            <h2>三步，让 Mac 发出你喜欢的声音。</h2>
            <p>当前版本无需 Apple Developer 账号即可安装，但尚未经过 Apple 公证，因此第一次打开需要手动允许。</p>
          </div>

          <div className="install-grid">
            {installSteps.map((step) => (
              <article key={step.number}>
                <span>{step.number}</span>
                <h3>{step.title}</h3>
                <p>{step.body}</p>
              </article>
            ))}
          </div>

          <div className="download-panel">
            <img src="/battuta-icon.png" alt="" />
            <div>
              <p className="download-version">Battuta 1.0.0 for macOS</p>
              <h3>现在，给下一次敲击一个声音。</h3>
              <p>Universal App · macOS 13+ · 约 8 MB · MIT 开源</p>
            </div>
            <div className="download-actions">
              <a className="button button-dark" href={downloadHref} download>下载 DMG</a>
              <a className="text-link" href="https://github.com/wormforce/battuta/releases/latest" target="_blank" rel="noreferrer">GitHub 备用下载 ↗</a>
            </div>
          </div>
        </div>
      </section>

      <section className="faq-section light-section">
        <div className="section-inner faq-grid">
          <div>
            <p className="section-kicker green">常见问题</p>
            <h2>安装之前，<br />你可能还想知道。</h2>
          </div>
          <div className="faq-list">
            {faqItems.map((item) => (
              <details key={item.question}>
                <summary>{item.question}<span>＋</span></summary>
                <p>{item.answer}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      <footer>
        <div className="footer-inner">
          <a className="brand-lockup" href="#top">
            <img src="/battuta-icon.png" alt="" />
            <span>Battuta</span>
          </a>
          <p>给每一次输入，配上你喜欢的声音。</p>
          <div>
            <a href="https://github.com/wormforce/battuta" target="_blank" rel="noreferrer">GitHub</a>
            <a href="https://github.com/wormforce/battuta/blob/main/LICENSE" target="_blank" rel="noreferrer">MIT License</a>
          </div>
        </div>
      </footer>
    </main>
  );
}
