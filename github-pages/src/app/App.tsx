import { useState } from 'react';
import {
	Copy,
	Check,
	Github,
	AlertCircle,
	Battery,
	Power,
	Zap,
	PlayCircle,
} from 'lucide-react';

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
							Auto-Shutdown after Sleep
						</div>
					</div>

					<h1 className="text-5xl md:text-7xl font-bold mb-6 bg-gradient-to-r from-blue-400 via-purple-400 to-pink-400 bg-clip-text text-transparent">
						Steam Deck Smart Sleep
					</h1>

					<div className="text-left max-w-2xl mx-auto space-y-4 text-slate-300">
						<p className="text-center">
							Stop losing{' '}
							<strong className="text-white">1% battery per hour</strong> in
							sleep mode. This fix automatically shuts down your Steam Deck
							after a configurable delay to prevent battery drain.
						</p>

						<div className="bg-purple-500/10 border border-purple-500/30 rounded-lg p-4 space-y-3">
							<h3 className="font-semibold text-white flex items-center gap-2">
								<PlayCircle className="w-5 h-5 text-purple-400" />
								Use Case:
							</h3>
							<div className="text-sm text-slate-300 space-y-3 ml-7">
								<div className="space-y-2">
									<div className="flex items-start gap-2">
										<span className="text-purple-400 font-bold">1.</span>
										<span>Device enters sleep and sets a wake timer</span>
									</div>
									<div className="flex items-start gap-2">
										<span className="text-purple-400 font-bold">2.</span>
										<span>
											Wakes up after configured delay (default: 3 hours)
										</span>
									</div>
									<div className="flex items-start gap-2">
										<span className="text-purple-400 font-bold">3.</span>
										<span>Checks charger connection</span>
									</div>
									<div className="flex items-start gap-2 ml-4">
										<Battery className="w-4 h-4 text-emerald-400 mt-0.5 flex-shrink-0" />
										<span>
											<strong className="text-white">If charging:</strong>{' '}
											Returns to sleep, repeats cycle
										</span>
									</div>
									<div className="flex items-start gap-2 ml-4">
										<Power className="w-4 h-4 text-slate-400 mt-0.5 flex-shrink-0" />
										<span>
											<strong className="text-white">If not charging:</strong>{' '}
											Powers off to preserve battery
										</span>
									</div>
								</div>
								<p className="text-purple-200/80 italic pt-1">
									Prevents battery drain on the go while keeping your device
									ready when plugged in. Manual wake cancels auto-shutdown.
								</p>
							</div>
						</div>

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

						<div className="bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-4 space-y-3">
							<h3 className="font-semibold text-white flex items-center gap-2">
								<Zap className="w-5 h-5 text-emerald-400" />
								Smart Charger Detection:
							</h3>
							<div className="text-sm text-slate-300 space-y-2 ml-7">
								<p>
									The script intelligently detects your charging status when the
									wake timer triggers:
								</p>
								<div className="space-y-2">
									<div className="flex items-start gap-2">
										<Battery className="w-4 h-4 text-emerald-400 mt-0.5 flex-shrink-0" />
										<span>
											<strong className="text-white">
												Connected & charging:
											</strong>{' '}
											Returns to sleep mode automatically
										</span>
									</div>
									<div className="flex items-start gap-2">
										<Power className="w-4 h-4 text-slate-400 mt-0.5 flex-shrink-0" />
										<span>
											<strong className="text-white">
												Disconnected or not charging:
											</strong>{' '}
											Initiates shutdown to preserve battery
										</span>
									</div>
								</div>
							</div>
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
										device shuts down—the same data loss that would occur if you
										left it in sleep mode until the battery fully discharged.
									</p>
								</div>
							</div>
						</div>
					</div>
				</div>

				{/* Security Warning */}
				<div className="w-full max-w-3xl mb-6">
					<div className="bg-red-500/10 border border-red-500/30 rounded-xl p-5">
						<div className="flex gap-3">
							<AlertCircle className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" />
							<div className="text-sm text-red-200/90 space-y-2">
								<p className="font-semibold text-red-300">Security Notice:</p>
								<p>
									This script modifies system files and requires root access.{' '}
									<a
										href="https://github.com/sandro-sikic/steam-deck-smart-sleep"
										target="_blank"
										rel="noopener noreferrer"
										className="text-white hover:text-blue-300 underline font-semibold transition-colors"
									>
										Please verify the source code
									</a>{' '}
									on GitHub before installation to ensure it's safe for your
									system.
								</p>
								<p className="text-red-300/80 italic">
									The developer is not responsible for any damage caused by this
									program. Use at your own risk.
								</p>
							</div>
						</div>
					</div>
				</div>

				{/* Command Box */}
				<div className="w-full max-w-3xl">
					<div className="relative bg-gradient-to-br from-slate-800/60 to-slate-900/60 backdrop-blur-md border border-slate-600/50 rounded-2xl p-8 shadow-2xl hover:shadow-blue-500/10 transition-shadow">
						<div className="absolute inset-0 bg-gradient-to-br from-blue-500/5 to-purple-500/5 rounded-2xl"></div>

						<div className="relative">
							<div className="flex items-center justify-between mb-6">
								<div>
									<span className="text-xs font-semibold text-slate-500 uppercase tracking-wider block mb-1">
										Quick Install
									</span>
									<span className="text-sm text-slate-300">
										Run this command in your Steam Deck terminal
									</span>
								</div>
								<button
									onClick={handleCopy}
									className="flex items-center gap-2 px-5 py-2.5 bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-500 hover:to-blue-600 rounded-lg transition-all font-medium shadow-lg shadow-blue-500/20 hover:shadow-blue-500/30 hover:scale-105"
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

							<div className="bg-slate-950/80 border border-slate-700/50 rounded-xl p-5 overflow-x-auto shadow-inner">
								<code className="text-green-400 font-mono text-sm md:text-base break-all">
									{command}
								</code>
							</div>
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
