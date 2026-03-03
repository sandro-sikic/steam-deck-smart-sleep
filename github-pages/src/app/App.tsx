import { useState } from 'react';
import { Copy, Check, Github, AlertCircle, Battery, Power } from 'lucide-react';

export default function App() {
	const [copied, setCopied] = useState(false);
	const command =
		'curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main/install.sh | sudo bash';

	const handleCopy = async () => {
		await navigator.clipboard.writeText(command);
		setCopied(true);
		setTimeout(() => setCopied(false), 2000);
	};

	return (
		<div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 text-white">
			{/* GitHub Link */}
			<div className="absolute top-6 right-6">
				<a
					href="https://github.com/sandro-sikic/steam-deck-smart-sleep"
					target="_blank"
					rel="noopener noreferrer"
					className="flex items-center gap-2 px-4 py-2 bg-white/10 hover:bg-white/20 rounded-lg transition-colors backdrop-blur-sm"
				>
					<Github className="w-5 h-5" />
					<span>View on GitHub</span>
				</a>
			</div>

			{/* Main Content */}
			<div className="flex flex-col items-center justify-center min-h-screen px-4 py-20">
				{/* Hero Section */}
				<div className="text-center max-w-4xl mx-auto mb-12">
					<div className="mb-6 inline-block">
						<div className="px-4 py-2 bg-blue-500/20 border border-blue-500/30 rounded-full text-blue-300 text-sm font-medium">
							Auto-Shutdown after long Sleep
						</div>
					</div>

					<h1 className="text-5xl md:text-7xl font-bold mb-6 bg-gradient-to-r from-blue-400 via-purple-400 to-pink-400 bg-clip-text text-transparent">
						Steam Deck Smart Sleep
					</h1>

					<p className="text-xl md:text-2xl text-slate-300 mb-6">
						Automatically shutdown your Steam Deck during sleep to eliminate
						battery drain
					</p>

					<div className="text-left max-w-2xl mx-auto space-y-4 text-slate-300">
						<p>
							Your Steam Deck drains approximately{' '}
							<strong className="text-white">1% battery per hour</strong> in
							sleep mode. This fix automatically shuts down your device after a
							configurable delay when it enters sleep, preventing unintentional
							battery drain during transport.
						</p>

						<div className="bg-slate-800/30 border border-slate-700 rounded-lg p-4 space-y-2">
							<h3 className="font-semibold text-white flex items-center gap-2">
								<Power className="w-5 h-5 text-blue-400" />
								How it works:
							</h3>
							<ul className="space-y-2 text-sm text-slate-300 ml-7">
								<li>
									• Sets an RTC alarm when your Steam Deck enters sleep mode
								</li>
								<li>
									• After your configured timeout, the device wakes briefly
								</li>
								<li>
									• Automatically performs a clean shutdown to preserve battery
								</li>
								<li>
									• If you wake the device manually before the timer, the
									shutdown is canceled
								</li>
							</ul>
						</div>

						<div className="bg-amber-500/10 border border-amber-500/30 rounded-lg p-4">
							<div className="flex gap-3">
								<AlertCircle className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
								<div>
									<p className="font-semibold text-amber-300 mb-1">
										Important:
									</p>
									<p className="text-sm text-amber-200/90">
										Always save your game progress before putting your Steam
										Deck to sleep. All in-memory data will be lost when the
										device shuts down.
									</p>
								</div>
							</div>
						</div>
					</div>
				</div>

				{/* Command Box */}
				<div className="w-full max-w-3xl">
					<div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-xl p-6 shadow-2xl">
						<div className="flex items-center justify-between mb-4">
							<span className="text-sm font-semibold text-slate-400 uppercase tracking-wider">
								Installation Command
							</span>
							<button
								onClick={handleCopy}
								className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors font-medium"
							>
								{copied ? (
									<>
										<Check className="w-4 h-4" />
										Copied!
									</>
								) : (
									<>
										<Copy className="w-4 h-4" />
										Copy
									</>
								)}
							</button>
						</div>

						<div className="bg-slate-900 rounded-lg p-4 overflow-x-auto">
							<code className="text-green-400 font-mono text-sm md:text-base break-all">
								{command}
							</code>
						</div>
					</div>
				</div>

				{/* Footer */}
				<div className="mt-16 text-slate-500 text-sm">
					<p>Open source and community-driven</p>
				</div>
			</div>
		</div>
	);
}
