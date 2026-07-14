export function AboutPage() {
  const year = new Date().getFullYear();

  return (
    <div
      className="relative flex flex-col bg-black text-white overflow-hidden"
      style={{ width: 390, height: 845, fontFamily: "'SF Pro Text', 'Helvetica Neue', Arial, sans-serif" }}
    >
      {/* Center content */}
      <div className="flex-1 flex flex-col items-center justify-center text-center px-8">
        {/* App name */}
        <h1
          style={{
            fontSize: 32,
            fontWeight: 700,
            letterSpacing: -0.5,
            color: "#FFFFFF",
            marginBottom: 6,
          }}
        >
          Music Player
        </h1>

        {/* Version */}
        <p style={{ fontSize: 15, color: "#8E8E93", marginBottom: 28 }}>
          Versi 1.0.0
        </p>

        {/* Divider */}
        <div
          style={{
            width: 48,
            height: 1,
            backgroundColor: "#3A3A3C",
            marginBottom: 28,
          }}
        />

        {/* Made by */}
        <p style={{ fontSize: 15, color: "#EBEBF0", marginBottom: 4 }}>
          Dibuat dengan dedikasi oleh
        </p>
        <p style={{ fontSize: 17, fontWeight: 700, color: "#FFFFFF" }}>
          Wndavenznchole
        </p>
      </div>

      {/* Footer */}
      <div className="pb-8 flex justify-center">
        <p style={{ fontSize: 13, color: "#636366" }}>
          © {year} Flutter Music App × Apple Music
        </p>
      </div>
    </div>
  );
}
