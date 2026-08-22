(function registerProfiles(root) {
  const profiles = [
    { id: "holypanda", name: "Holy Panda", family: "段落", tone: "饱满、集中" },
    { id: "mxbrown", name: "Cherry MX Brown", family: "段落", tone: "温和、均衡" },
    { id: "mxblue", name: "Cherry MX Blue", family: "点击", tone: "清脆、经典", genericOnly: true },
    { id: "boxnavy", name: "Kailh BOX Navy", family: "点击", tone: "厚重、响亮" },
    { id: "bluealps", name: "SKCM Blue Alps", family: "点击", tone: "复古、锐利" },
    { id: "cream", name: "NovelKeys Cream", family: "线性", tone: "顺滑、奶油" },
    { id: "alpaca", name: "Alpaca", family: "线性", tone: "干净、柔和" },
    { id: "blackink", name: "Gateron Black Ink", family: "线性", tone: "低沉、扎实" },
    { id: "redink", name: "Gateron Red Ink", family: "线性", tone: "轻快、圆润" },
    { id: "mxblack", name: "Cherry MX Black", family: "线性", tone: "沉稳、硬朗" },
    { id: "turquoise", name: "Turquoise Tealios", family: "线性", tone: "明亮、顺滑" },
    { id: "topre", name: "Topre", family: "静电容", tone: "柔韧、闷响" },
    { id: "buckling", name: "IBM Buckling Spring", family: "屈曲弹簧", tone: "复古、金属感" }
  ];

  root.SIMUBOARD_PROFILES = Object.freeze(profiles.map(Object.freeze));
})(globalThis);
