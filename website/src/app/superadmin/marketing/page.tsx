"use client";

import React, { useEffect, useState } from "react";
import axios from "axios";
import { PageHeader } from "@/components/ui/PageHeader";
import { Container } from "@/components/ui/Container";

interface Variable {
    key: string;
    label: string;
    description: string;
    example: string;
}

interface Automation {
    id: string;
    key: string;
    name: string;
    description: string;
    audience: string;
    frequency_label: string;
    is_enabled: boolean;
    aisensy_campaign_name: string | null;
    lead_time_minutes: number | null;
    variables: Variable[];
    health: {
        status: string;
        last_run_at: string | null;
        last_success_at: string | null;
        last_failure_at: string | null;
        recent_success_count?: number;
        recent_failure_count?: number;
    };
}

export default function WhatsappAutomationsPage() {
    const [automations, setAutomations] = useState<Automation[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [editingKey, setEditingKey] = useState<string | null>(null);
    const [editData, setEditData] = useState<{
        is_enabled: boolean;
        aisensy_campaign_name: string;
        lead_time_minutes: number | null;
    } | null>(null);

    const [testPhone, setTestPhone] = useState("");
    const [testingKey, setTestingKey] = useState<string | null>(null);
    const [testStatus, setTestStatus] = useState<{ type: 'success' | 'error', message: string } | null>(null);

    useEffect(() => {
        fetchAutomations();
    }, []);

    const fetchAutomations = async () => {
        try {
            const response = await axios.get("/api/proxy/superadmin/whatsapp-automations");
            if (response.data.success) {
                setAutomations(response.data.data);
            }
        } catch (error) {
            console.error("Failed to load automations", error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleEdit = (automation: Automation) => {
        setEditingKey(automation.key);
        setEditData({
            is_enabled: automation.is_enabled,
            aisensy_campaign_name: automation.aisensy_campaign_name || "",
            lead_time_minutes: automation.lead_time_minutes,
        });
    };

    const handleSave = async (key: string) => {
        if (!editData) return;

        try {
            const response = await axios.put(`/api/proxy/superadmin/whatsapp-automations/${key}`, editData);
            if (response.data.success) {
                setEditingKey(null);
                setEditData(null);
                fetchAutomations();
            }
        } catch (error: any) {
            alert(error.response?.data?.message || "Failed to update automation.");
        }
    };

    const handleTest = async (key: string) => {
        if (!testPhone) {
            alert("Please enter a phone number to test.");
            return;
        }

        setTestingKey(key);
        setTestStatus(null);
        try {
            const response = await axios.post(`/api/proxy/superadmin/whatsapp-automations/${key}/test`, {
                phone: testPhone,
            });
            if (response.data.success) {
                setTestStatus({ type: 'success', message: 'Test message sent successfully.' });
            }
        } catch (error: any) {
            setTestStatus({ type: 'error', message: error.response?.data?.message || 'Failed to send test message.' });
        } finally {
            setTestingKey(null);
        }
    };

    const getStatusBadge = (status: string) => {
        switch (status) {
            case 'WORKING': return <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">🟢 Working</span>;
            case 'READY': return <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">🟢 Ready</span>;
            case 'DISABLED': return <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">⚪ Disabled</span>;
            case 'NOT_CONFIGURED': return <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">🔴 Not Configured</span>;
            case 'NEEDS_ATTENTION': return <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">🟡 Needs Attention</span>;
            case 'FAILING': return <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">🔴 Failing</span>;
            default: return <span>{status}</span>;
        }
    };

    if (isLoading) {
        return <div className="p-8 text-center text-gray-500">Loading automations...</div>;
    }

    return (
        <Container>
            <PageHeader
                title="WhatsApp Automations"
                description="Manage automated system WhatsApp messages sent by BookALook."
            />

            <div className="grid grid-cols-1 xl:grid-cols-2 gap-6 mt-6">
                {automations.map((automation) => (
                    <div key={automation.key} className="bg-white rounded-lg shadow border border-gray-200 overflow-hidden">
                        <div className="px-6 py-4 border-b border-gray-200 bg-gray-50 flex justify-between items-center">
                            <h3 className="text-lg font-medium text-gray-900">{automation.name}</h3>
                            <div className="flex items-center">
                                {getStatusBadge(automation.health.status)}
                            </div>
                        </div>

                        <div className="p-6">
                            <p className="text-sm text-gray-600 mb-6">{automation.description}</p>

                            <div className="grid grid-cols-2 gap-6 mb-6">
                                <div>
                                    <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Who</h4>
                                    <p className="text-sm text-gray-900">{automation.audience}</p>
                                </div>
                                <div>
                                    <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">When</h4>
                                    <p className="text-sm text-gray-900">{automation.frequency_label}</p>
                                </div>
                            </div>

                            <div className="mb-6 bg-gray-50 rounded-md p-4 border border-gray-200">
                                <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">AiSensy Campaign</h4>
                                {editingKey === automation.key ? (
                                    <input 
                                        type="text" 
                                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" 
                                        value={editData?.aisensy_campaign_name} 
                                        onChange={e => setEditData(prev => prev ? {...prev, aisensy_campaign_name: e.target.value} : null)}
                                        placeholder="e.g. BAL_CUSTOMER_BIRTHDAY"
                                    />
                                ) : (
                                    <div className="flex items-center">
                                        <p className="text-sm font-medium text-gray-900 mr-3">
                                            {automation.aisensy_campaign_name || <span className="text-gray-400 italic">Not configured</span>}
                                        </p>
                                        {automation.aisensy_campaign_name && (
                                            <span className="text-green-600 text-xs flex items-center">
                                                <svg className="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7" /></svg>
                                                Configured
                                            </span>
                                        )}
                                    </div>
                                )}
                            </div>

                            {automation.key === 'whatsapp_appointment_reminder' && editingKey === automation.key && (
                                <div className="mb-6">
                                    <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Lead Time (Minutes)</h4>
                                    <input 
                                        type="number" 
                                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" 
                                        value={editData?.lead_time_minutes || ''} 
                                        onChange={e => setEditData(prev => prev ? {...prev, lead_time_minutes: parseInt(e.target.value)} : null)}
                                        min="1"
                                    />
                                    <p className="mt-1 text-xs text-gray-500">E.g., 120 for 2 hours before appointment.</p>
                                </div>
                            )}

                            {automation.variables.length > 0 && (
                                <div className="mb-6">
                                    <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Required Variables (in exact order)</h4>
                                    <ul className="text-sm text-gray-700 space-y-2">
                                        {automation.variables.map((v, idx) => (
                                            <li key={v.key} className="flex flex-col">
                                                <span className="font-mono bg-gray-100 px-1 rounded inline-block w-max mb-1">{idx + 1}. {`{{${v.key}}}`}</span>
                                                <span className="text-gray-500 text-xs ml-4">E.g. {v.example} ({v.label})</span>
                                            </li>
                                        ))}
                                    </ul>
                                </div>
                            )}

                            {editingKey === automation.key ? (
                                <div className="flex items-center justify-between mt-6 pt-4 border-t border-gray-200">
                                    <div className="flex items-center">
                                        <input
                                            type="checkbox"
                                            id={`enable-${automation.key}`}
                                            checked={editData?.is_enabled}
                                            disabled={automation.key === 'whatsapp_otp'}
                                            onChange={e => setEditData(prev => prev ? {...prev, is_enabled: e.target.checked} : null)}
                                            className="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                                        />
                                        <label htmlFor={`enable-${automation.key}`} className="ml-2 block text-sm text-gray-900">
                                            Enable Automation
                                        </label>
                                    </div>
                                    <div className="flex space-x-3">
                                        <button onClick={() => setEditingKey(null)} className="px-3 py-1.5 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50">
                                            Cancel
                                        </button>
                                        <button onClick={() => handleSave(automation.key)} className="px-3 py-1.5 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700">
                                            Save Changes
                                        </button>
                                    </div>
                                </div>
                            ) : (
                                <div className="mt-6 pt-4 border-t border-gray-200">
                                    <div className="flex justify-between items-center mb-4">
                                        <button onClick={() => handleEdit(automation)} className="text-indigo-600 hover:text-indigo-900 text-sm font-medium">
                                            Edit Configuration
                                        </button>
                                        <div className="text-xs text-gray-500 text-right">
                                            {automation.health.last_run_at ? `Last run: ${new Date(automation.health.last_run_at).toLocaleString()}` : 'Never run'}
                                        </div>
                                    </div>

                                    {automation.key !== 'whatsapp_otp' && automation.is_enabled && automation.aisensy_campaign_name && (
                                        <div className="bg-blue-50 p-4 rounded-md flex items-center space-x-3">
                                            <input 
                                                type="text"
                                                placeholder="+91XXXXXXXXXX"
                                                className="block w-full sm:text-sm border-gray-300 rounded-md"
                                                value={testPhone}
                                                onChange={e => setTestPhone(e.target.value)}
                                            />
                                            <button 
                                                onClick={() => handleTest(automation.key)} 
                                                disabled={testingKey === automation.key}
                                                className="whitespace-nowrap px-3 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50"
                                            >
                                                {testingKey === automation.key ? 'Sending...' : 'Send Test'}
                                            </button>
                                        </div>
                                    )}
                                    {testStatus && testingKey === null && automation.key !== 'whatsapp_otp' && automation.is_enabled && (
                                        <p className={`mt-2 text-xs ${testStatus.type === 'success' ? 'text-green-600' : 'text-red-600'}`}>
                                            {testStatus.message}
                                        </p>
                                    )}
                                </div>
                            )}

                        </div>
                    </div>
                ))}
            </div>
        </Container>
    );
}
